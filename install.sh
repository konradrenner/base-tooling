#!/usr/bin/env bash
set -euo pipefail

# base-tooling install (Day-0)
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/<org>/<repo>/main/install.sh | bash -s -- --user <name>

msg()  { printf '\n==> %s\n\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
err()  { printf 'ERROR: %s\n' "$*" >&2; }

usage() {
  cat <<'USAGE'
Usage: install.sh --user <username>

Options:
  --user <name>     Username to configure (required)
  --dir <path>      Install directory (default: ~/.base-tooling)
  -h, --help        Show help
USAGE
}

is_darwin() { [[ "$(uname -s)" == "Darwin" ]]; }
arch() { uname -m; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Missing required command: $1"; exit 1; }
}

require_sudo() {
  if ! sudo -n true 2>/dev/null; then
    msg "Sudo privileges required. You may be prompted for your password."
    sudo true
  fi
}

ensure_nix_conf_flakes() {
  msg "Enabling nix-command + flakes (idempotent)."

  # Prefer per-user nix.conf; this avoids /etc/nix/nix.conf clobber issues on Linux.
  local nix_conf_dir="$HOME/.config/nix"
  local nix_conf_file="$nix_conf_dir/nix.conf"
  mkdir -p "$nix_conf_dir"

  # Keep any existing content, just ensure experimental-features are present.
  if [[ ! -f "$nix_conf_file" ]]; then
    printf 'experimental-features = nix-command flakes\n' > "$nix_conf_file"
  else
    if ! grep -q '^experimental-features *=.*\bflakes\b' "$nix_conf_file" 2>/dev/null; then
      # Append safely; if there's already experimental-features without flakes, add another line.
      printf '\nexperimental-features = nix-command flakes\n' >> "$nix_conf_file"
    fi
  fi
}

ensure_nix_installed() {
  if command -v nix >/dev/null 2>&1; then
    msg "Nix already installed."
    return
  fi

  msg "Installing Nix (Determinate Systems installer)."
  require_cmd curl
  sh <(curl -L https://install.determinate.systems/nix) install

  # Try to source profile if available (best-effort)
  if [[ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]]; then
    # shellcheck disable=SC1091
    . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
  fi
}

ensure_homebrew_darwin() {
  if ! is_darwin; then return; fi

  if command -v brew >/dev/null 2>&1; then
    msg "Homebrew already installed."
    return
  fi

  msg "Installing Homebrew (macOS)."
  require_cmd curl
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Best-effort: ensure brew in PATH for this process
  if [[ -x /opt/homebrew/bin/brew ]]; then
    export PATH="/opt/homebrew/bin:$PATH"
  fi
}

ensure_git() {
  if command -v git >/dev/null 2>&1; then
    msg "git already installed."
    return
  fi

  msg "Installing git."
  if is_darwin; then
    # Usually already present via Xcode CLT; prompt install if needed
    xcode-select --install || true
  else
    require_sudo
    sudo apt-get update -y
    sudo apt-get install -y git
  fi
}

ensure_repo() {
  local repo_url="$1"
  local install_dir="$2"

  msg "Ensuring repo is present at: $install_dir"

  if [[ -d "$install_dir/.git" ]]; then
    msg "Repo already cloned. Fetching latest..."
    git -C "$install_dir" fetch --all --prune
    git -C "$install_dir" checkout -q main || true
    git -C "$install_dir" pull --ff-only || true
    return
  fi

  msg "Cloning repo..."
  git clone "$repo_url" "$install_dir"
}

install_rancher_desktop_linux_repo() {
  msg "Linux: Installing Rancher Desktop via official repository..."

  # If rancher-desktop is already present, don't touch apt sources.
  if command -v rancher-desktop >/dev/null 2>&1 || command -v rancher-desktopctl >/dev/null 2>&1; then
    msg "Rancher Desktop already installed."
    return
  fi

  require_sudo
  require_cmd curl
  require_cmd gpg

  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl gnupg

  # Rancher Desktop upstream currently publishes apt repo at downloads.rancherdesktop.io
  # (Avoid rpm.rancher.io/deb which 404s).
  local keyring='/usr/share/keyrings/rancher-desktop-archive-keyring.gpg'
  local list='/etc/apt/sources.list.d/rancher-desktop.list'

  if [[ ! -f "$keyring" ]]; then
    curl -fsSL https://downloads.rancherdesktop.io/public-key.gpg | sudo gpg --dearmor -o "$keyring"
    sudo chmod 0644 "$keyring"
  fi

  # Detect Ubuntu codename
  local codename
  codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}" )"
  if [[ -z "$codename" ]]; then
    codename="stable"
  fi

  # Repo layout is 'deb [signed-by=...] https://downloads.rancherdesktop.io/deb/ <codename> main'
  # If codename isn't supported, 'stable' typically works.
  echo "deb [arch=$(dpkg --print-architecture) signed-by=$keyring] https://downloads.rancherdesktop.io/deb/ ${codename} main" | sudo tee "$list" >/dev/null

  # Update and install
  sudo apt-get update -y
  sudo apt-get install -y rancher-desktop
}

ensure_linux_zsh() {
  if ! command -v zsh >/dev/null 2>&1; then
    log "Installing zsh..."
    sudo apt-get update -y
    sudo apt-get install -y zsh
  fi

  local ZSH_PATH
  ZSH_PATH="$(command -v zsh)"

  if ! grep -qxF "$ZSH_PATH" /etc/shells; then
    echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
  fi

  if [ "$(getent passwd "$USERNAME" | cut -d: -f7)" != "$ZSH_PATH" ]; then
    log "Setting zsh as default shell for $USERNAME"
    sudo chsh -s "$ZSH_PATH" "$USERNAME"
  fi
}

ensure_home_manager_cli() {
  # Ensure `home-manager` command exists (needed for: home-manager news, generations, etc.)
  if command -v home-manager >/dev/null 2>&1; then
    return
  fi

  msg "Ensuring home-manager CLI is installed (nix profile)."
  # This is user-scoped and safe on both Linux and macOS.
  # Use explicit experimental-features in case nix.conf isn't picked up in non-interactive shells.
  nix profile install \
    --extra-experimental-features nix-command \
    --extra-experimental-features flakes \
    github:nix-community/home-manager
}

ensure_linux_zsh() {
  if ! command -v zsh >/dev/null 2>&1; then
    log "Installing zsh..."
    sudo apt-get update -y
    sudo apt-get install -y zsh
  fi

  local ZSH_PATH
  ZSH_PATH="$(command -v zsh)"

  if ! grep -qxF "$ZSH_PATH" /etc/shells; then
    echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
  fi

  if [ "$(getent passwd "$USERNAME" | cut -d: -f7)" != "$ZSH_PATH" ]; then
    log "Setting zsh as default shell for $USERNAME"
    sudo chsh -s "$ZSH_PATH" "$USERNAME"
  fi
}

apply_configuration() {
  msg "Applying declarative configuration..."
  export BASE_TOOLING_USER="$USERNAME"

  if is_darwin; then
    require_sudo

    # Build system configuration (user context). --impure needed for BASE_TOOLING_USER via getEnv.
    nix build --impure "$INSTALL_DIR#darwinConfigurations.${DARWIN_TARGET}.system"

    # Activate as root (propagate BASE_TOOLING_USER into sudo env)
    sudo --preserve-env=BASE_TOOLING_USER ./result/sw/bin/darwin-rebuild switch --impure --flake "$INSTALL_DIR#${DARWIN_TARGET}"

    # Ensure HM CLI is available for convenience
    ensure_home_manager_cli
  else
    # Linux Home Manager configuration for "<user>@linux"
    nix run github:nix-community/home-manager -- \
      switch \
      --impure \
      --flake "$INSTALL_DIR#${USERNAME}@linux" \
      -b backup

    ensure_home_manager_cli
    ensure_linux_zsh

    msg "Open a NEW terminal so PATH updates take effect."
  fi
}

# -----------------
# Argument parsing
# -----------------
USERNAME=""
INSTALL_DIR="${HOME}/.base-tooling"
DARWIN_TARGET="default"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      USERNAME="$2"; shift 2;;
    --dir)
      INSTALL_DIR="$2"; shift 2;;
    -h|--help)
      usage; exit 0;;
    *)
      err "Unknown argument: $1"; usage; exit 1;;
  esac
done

if [[ -z "$USERNAME" ]]; then
  err "--user is required"; usage; exit 1
fi

msg "Base tooling install (Day-0) starting..."

if is_darwin; then
  msg "Detected OS: Darwin ($(arch))"
else
  msg "Detected OS: Linux ($(arch))"
fi

msg "Using user: $USERNAME"
msg "Repo dir: $INSTALL_DIR"

ensure_nix_installed
ensure_nix_conf_flakes
ensure_homebrew_darwin
ensure_git

# Clone/update repo (change this to your repo URL)
REPO_URL="https://github.com/konradrenner/base-tooling"
ensure_repo "$REPO_URL" "$INSTALL_DIR"

# Platform-specific extras
if ! is_darwin; then
  install_rancher_desktop_linux_repo
fi

apply_configuration

msg "Done."
