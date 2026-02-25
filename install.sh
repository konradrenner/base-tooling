#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Logging / Helpers
# -----------------------------
msg() { echo -e "\n==> $*"; }
warn() { echo -e "WARN: $*" >&2; }
die() { echo -e "ERROR: $*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

is_darwin() { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux()  { [[ "$(uname -s)" == "Linux"  ]]; }

arch() {
  # normalize
  local a
  a="$(uname -m)"
  case "$a" in
    x86_64|amd64) echo "x86_64" ;;
    aarch64|arm64) echo "aarch64" ;;
    *) echo "$a" ;;
  esac
}

require_sudo() {
  msg "Sudo privileges required. You may be prompted for your password."
  sudo -v
}

usage() {
  cat <<'EOF'
Usage:
  install.sh --user <name> [--dir <path>]

Notes:
- Exports BASE_TOOLING_USER=<name> for nix flake evaluation (--impure).
- On macOS, applies nix-darwin + home-manager.
- On Linux, applies home-manager standalone.

EOF
}

# -----------------------------
# Args
# -----------------------------
USERNAME=""
INSTALL_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      USERNAME="${2:-}"; shift 2 ;;
    --dir)
      INSTALL_DIR="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      die "Unknown argument: $1" ;;
  esac
done

[[ -n "$USERNAME" ]] || { usage; die "--user is required"; }

# Default install dir per OS
if [[ -z "$INSTALL_DIR" ]]; then
  if is_darwin; then
    INSTALL_DIR="/Users/${USERNAME}/.base-tooling"
  else
    # If the user exists, respect their home dir; else fall back.
    if have getent && getent passwd "$USERNAME" >/dev/null 2>&1; then
      INSTALL_DIR="$(getent passwd "$USERNAME" | cut -d: -f6)/.base-tooling"
    else
      INSTALL_DIR="$HOME/.base-tooling"
      warn "User '$USERNAME' not found via getent; using INSTALL_DIR=$INSTALL_DIR"
    fi
  fi
fi

# -----------------------------
# Detect OS
# -----------------------------
OS="$(uname -s)"
CPU_ARCH="$(arch)"

msg "Base tooling install (Day-0) starting..."
msg "Detected OS: ${OS} (${CPU_ARCH})"
msg "Using user: ${USERNAME}"
msg "Repo dir: ${INSTALL_DIR}"

# -----------------------------
# Ensure nix + basic deps
# -----------------------------
enable_flakes() {
  msg "Enabling nix-command + flakes (idempotent)."
  mkdir -p "$HOME/.config/nix"
  local conf="$HOME/.config/nix/nix.conf"
  touch "$conf"
  # Ensure both lines exist (without duplicating)
  grep -q '^experimental-features' "$conf" 2>/dev/null || echo "experimental-features = nix-command flakes" >> "$conf"
  grep -q '^accept-flake-config' "$conf" 2>/dev/null || echo "accept-flake-config = true" >> "$conf"
}

ensure_nix() {
  if have nix; then
    msg "Nix already installed."
    return
  fi
  die "Nix is not installed. Install Nix first, then re-run."
}

ensure_git() {
  if have git; then
    msg "git already installed."
    return
  fi
  if is_darwin; then
    die "git missing on macOS. Install Xcode Command Line Tools or brew git."
  else
    require_sudo
    msg "Installing git..."
    sudo apt-get update -y
    sudo apt-get install -y git
  fi
}

ensure_homebrew() {
  if ! is_darwin; then return; fi
  if have brew; then
    msg "Homebrew already installed."
    return
  fi
  die "Homebrew missing. Please install Homebrew first."
}

ensure_repo() {
  msg "Ensuring repo is present at: ${INSTALL_DIR}"
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    msg "Repo already cloned. Fetching latest..."
    git -C "$INSTALL_DIR" fetch --all --prune
    # do not force-pull; keep it safe for "blueprint" use
    git -C "$INSTALL_DIR" pull --ff-only || warn "Could not fast-forward pull (local changes?). Continuing."
  else
    mkdir -p "$(dirname "$INSTALL_DIR")"
    msg "Cloning repo..."
    git clone "https://github.com/konradrenner/base-tooling" "$INSTALL_DIR"
  fi
}

# -----------------------------
# Linux: Rancher Desktop via official repo (x86_64 only)
# -----------------------------
install_rancher_desktop_linux_repo() {
  msg "Linux: Installing Rancher Desktop via official repository..."

  # Rancher Desktop on Linux requires x86_64 + /dev/kvm; on aarch64 we must skip.
  if [[ "$(arch)" != "x86_64" ]]; then
    warn "Rancher Desktop on Linux requires x86_64. Detected $(arch). Skipping Rancher Desktop install."
    warn "Alternative for ARM Linux: Podman + (optional) Podman Desktop, or Docker Engine (if available for your distro)."
    return 0
  fi

  if have rancher-desktop; then
    msg "Rancher Desktop already installed."
    return 0
  fi

  require_sudo

  # deps
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl gnupg

  # repo key + list (per Rancher Desktop docs for .deb)
  sudo install -d -m 0755 /usr/share/keyrings
  curl -fsSL "https://download.opensuse.org/repositories/isv:/Rancher:/stable/deb/Release.key" \
    | gpg --dearmor \
    | sudo dd status=none of=/usr/share/keyrings/isv-rancher-stable-archive-keyring.gpg

  echo "deb [signed-by=/usr/share/keyrings/isv-rancher-stable-archive-keyring.gpg] https://download.opensuse.org/repositories/isv:/Rancher:/stable/deb/ ./" \
    | sudo dd status=none of=/etc/apt/sources.list.d/isv-rancher-stable.list

  sudo apt-get update -y
  sudo apt-get install -y rancher-desktop

  msg "Rancher Desktop installed."
  msg "Note: Ensure you have RW access to /dev/kvm (often: sudo usermod -a -G kvm \"$USER\"; reboot)."
}

# -----------------------------
# Apply declarative configuration
# -----------------------------
apply_configuration() {
  msg "Applying declarative configuration..."
  export BASE_TOOLING_USER="${USERNAME}"

  if is_darwin; then
    require_sudo
    # Build into repo-local result to avoid confusion
    nix build --impure -o "${INSTALL_DIR}/result" "${INSTALL_DIR}#darwinConfigurations.default.system"
    # Activate as root; preserve env so getEnv works even under sudo
    sudo --preserve-env=BASE_TOOLING_USER "${INSTALL_DIR}/result/sw/bin/darwin-rebuild" switch --impure --flake "${INSTALL_DIR}#default"
  else
    # Optional: install Rancher Desktop for Linux (repo), if desired
    install_rancher_desktop_linux_repo || true

    # Linux Home Manager configuration for "<user>@linux"
    nix run github:nix-community/home-manager -- \
      switch -b backup \
      --impure \
      --flake "${INSTALL_DIR}#${USERNAME}@linux"
  fi
}

# -----------------------------
# Run
# -----------------------------
ensure_nix
enable_flakes
ensure_homebrew
ensure_git
ensure_repo
apply_configuration

msg "Done."
