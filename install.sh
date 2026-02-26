#!/usr/bin/env bash
set -euo pipefail

# base-tooling install (Day-0)
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/konradrenner/base-tooling/main/install.sh | bash -s -- --user <name>

#############################################
# utils
#############################################
msg() { printf '\n==> %s\n' "$*"; }
warn() { printf '\nWARN: %s\n' "$*" >&2; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

require_sudo() {
  if have sudo; then
    msg "Sudo privileges required. You may be prompted for your password."
    sudo -v
  else
    die "sudo is required but not found."
  fi
}

is_darwin() { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux() { [[ "$(uname -s)" == "Linux" ]]; }

arch() {
  # Normalize to common labels
  local a
  a="$(uname -m)"
  case "$a" in
    x86_64|amd64) echo "x86_64";;
    aarch64|arm64) echo "aarch64";;
    *) echo "$a";;
  esac
}

user_home() {
  # robust home resolution for the requested username
  local u="$1"
  if is_darwin; then
    dscl . -read "/Users/$u" NFSHomeDirectory 2>/dev/null | awk '{print $2}' || true
  else
    getent passwd "$u" 2>/dev/null | cut -d: -f6 || true
  fi
}

source_nix_profile_if_needed() {
  # Make nix available within this non-login shell.
  if have nix; then return 0; fi

  # Multi-user daemon profile scripts
  if [[ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  elif [[ -e /nix/var/nix/profiles/default/etc/profile.d/nix.sh ]]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix.sh
  fi

  # Single-user profile
  if [[ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
    # shellcheck disable=SC1091
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
  fi
}

#############################################
# args
#############################################
USERNAME=""
NO_PULL=0
DARWIN_TARGET="default"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USERNAME="${2:-}"; shift 2;;
    --no-pull) NO_PULL=1; shift;;
    --darwin-target) DARWIN_TARGET="${2:-default}"; shift 2;;
    -h|--help)
      cat <<EOF
Usage: install.sh --user <name> [--no-pull] [--darwin-target default]
EOF
      exit 0
      ;;
    *) die "Unknown argument: $1";;
  esac
done

[[ -n "$USERNAME" ]] || die "Missing --user <name>"

#############################################
# config
#############################################
OS="$(uname -s)"
ARCH="$(arch)"

msg "Base tooling install (Day-0) starting..."
msg "Detected OS: ${OS} (${ARCH})"
msg "Using user: ${USERNAME}"

HOME_DIR="$(user_home "$USERNAME")"
[[ -n "$HOME_DIR" ]] || die "Could not determine home directory for user '$USERNAME'"

INSTALL_DIR="${HOME_DIR}/.base-tooling"
msg "Repo dir: ${INSTALL_DIR}"

#############################################
# prerequisites (Nix / git / brew)
#############################################
ensure_git() {
  if have git; then
    msg "git already installed."
    return
  fi
  if is_darwin; then
    die "git not found. Install Xcode Command Line Tools or Homebrew first."
  else
    require_sudo
    msg "Installing git..."
    sudo apt-get update -y
    sudo apt-get install -y git
  fi
}

ensure_nix() {
  if have nix; then
    msg "Nix already installed."
    return
  fi
  die "Nix not found. Please install Nix first (multi-user recommended) and re-run."
}

enable_flakes_idempotent() {
  msg "Enabling nix-command + flakes (idempotent)."

  # On many setups this is already enabled; we still ensure the config line exists.
  # For multi-user installs, nix.conf is usually at /etc/nix/nix.conf.
  if is_darwin; then
    require_sudo
  fi

  local nix_conf
  if [[ -w /etc/nix/nix.conf || ( -e /etc/nix/nix.conf && ! -w /etc/nix/nix.conf ) ]]; then
    nix_conf="/etc/nix/nix.conf"
  else
    nix_conf="${HOME}/.config/nix/nix.conf"
    mkdir -p "$(dirname "$nix_conf")"
    touch "$nix_conf"
  fi

  if ! grep -q "^experimental-features" "$nix_conf" 2>/dev/null; then
    if [[ "$nix_conf" == "/etc/nix/nix.conf" ]]; then
      sudo sh -c "printf '\nexperimental-features = nix-command flakes\n' >> '$nix_conf'"
    else
      printf '\nexperimental-features = nix-command flakes\n' >> "$nix_conf"
    fi
  fi
}

ensure_homebrew_darwin() {
  if ! is_darwin; then return; fi
  if have brew; then
    msg "Homebrew already installed."
    return
  fi
  die "Homebrew not found. Please install Homebrew first and re-run."
}

#############################################
# repo
#############################################
ensure_repo() {
  msg "Ensuring repo is present at: ${INSTALL_DIR}"

  if [[ -d "$INSTALL_DIR/.git" ]]; then
    msg "Repo already cloned."
    if [[ "$NO_PULL" -eq 0 ]]; then
      msg "Fetching latest..."
      git -C "$INSTALL_DIR" fetch --all --prune
      git -C "$INSTALL_DIR" pull --ff-only
    else
      msg "--no-pull set; skipping git pull."
    fi
  else
    msg "Cloning repo..."
    git clone https://github.com/konradrenner/base-tooling.git "$INSTALL_DIR"
  fi
}

#############################################
# Rancher Desktop
#############################################
install_rancher_desktop_darwin() {
  # Installed via nix-darwin Homebrew module (Brewfile/cask) in config.
  :
}

install_rancher_desktop_linux() {
  # Goal:
  # - x86_64: prefer official OBS apt repo
  # - aarch64: fall back to GitHub release (.deb/.rpm) because OBS repo is amd64-only

  if ! is_linux; then return; fi

  if have rdctl || have rancher-desktop; then
    msg "Rancher Desktop already installed."
    return
  fi

  require_sudo

  if have apt-get; then
    if [[ "$ARCH" == "x86_64" ]]; then
      msg "Linux: Installing Rancher Desktop via official repository (apt, x86_64)."

      sudo apt-get update -y
      sudo apt-get install -y ca-certificates curl gnupg

      sudo install -d -m 0755 /etc/apt/keyrings
      curl -fsSL "https://download.opensuse.org/repositories/isv:/Rancher:/stable/deb/Release.key" | \
        gpg --dearmor | sudo tee /etc/apt/keyrings/rancher-desktop.gpg >/dev/null

      echo "deb [signed-by=/etc/apt/keyrings/rancher-desktop.gpg] https://download.opensuse.org/repositories/isv:/Rancher:/stable/deb/ /" | \
        sudo tee /etc/apt/sources.list.d/rancher-desktop.list >/dev/null

      sudo apt-get update -y
      sudo apt-get install -y rancher-desktop
      return
    fi

    msg "Linux: aarch64 detected; installing Rancher Desktop from GitHub release (.deb)"
    sudo apt-get update -y
    sudo apt-get install -y ca-certificates curl

    local api url tmp
    api="https://api.github.com/repos/rancher-sandbox/rancher-desktop/releases/latest"
    # pick the first .deb matching arm64/aarch64
    url="$(curl -fsSL "$api" | grep -Eo '"browser_download_url"\s*:\s*"[^"]+\.deb"' | cut -d'"' -f4 | grep -E '(arm64|aarch64)' | head -n1)"
    [[ -n "$url" ]] || die "Could not find an arm64/aarch64 .deb asset in latest Rancher Desktop release."

    tmp="/tmp/rancher-desktop_${ARCH}.deb"
    curl -fL "$url" -o "$tmp"
    sudo apt-get install -y "$tmp"
    rm -f "$tmp"
    return
  fi

  if have dnf || have yum; then
    msg "Linux: Installing Rancher Desktop from GitHub release (.rpm)"
    sudo (dnf -y install curl ca-certificates || yum -y install curl ca-certificates)
    local api url tmp
    api="https://api.github.com/repos/rancher-sandbox/rancher-desktop/releases/latest"
    url="$(curl -fsSL "$api" | grep -Eo '"browser_download_url"\s*:\s*"[^"]+\.rpm"' | cut -d'"' -f4 | grep -E "${ARCH}|x86_64|amd64|arm64|aarch64" | head -n1)"
    [[ -n "$url" ]] || die "Could not find a .rpm asset in latest Rancher Desktop release."
    tmp="/tmp/rancher-desktop_${ARCH}.rpm"
    curl -fL "$url" -o "$tmp"
    sudo (dnf -y install "$tmp" || yum -y localinstall "$tmp")
    rm -f "$tmp"
    return
  fi

  warn "No supported package manager detected (apt/dnf/yum). Skipping Rancher Desktop install."
}

#############################################
# Linux: make zsh default for the user
#############################################
ensure_linux_zsh_default() {
  if ! is_linux; then return; fi

  if [[ "$(getent passwd "$USERNAME" | cut -d: -f7)" == "/usr/bin/zsh" ]]; then
    msg "Linux: zsh already default shell for ${USERNAME}."
    return
  fi

  require_sudo
  msg "Linux: Installing system zsh and setting as default shell for ${USERNAME}."

  if have apt-get; then
    sudo apt-get update -y
    sudo apt-get install -y zsh
  elif have dnf; then
    sudo dnf -y install zsh
  elif have yum; then
    sudo yum -y install zsh
  else
    warn "No supported package manager found to install zsh."
  fi

  if [[ -x /usr/bin/zsh ]]; then
    if ! grep -q '^/usr/bin/zsh$' /etc/shells 2>/dev/null; then
      echo '/usr/bin/zsh' | sudo tee -a /etc/shells >/dev/null
    fi
    sudo chsh -s /usr/bin/zsh "$USERNAME" || warn "Could not change shell automatically (chsh). You can run: chsh -s /usr/bin/zsh"
  else
    warn "/usr/bin/zsh not found; cannot set default shell."
  fi
}

#############################################
# Home Manager
#############################################
ensure_home_manager_command() {
  # Ensure a stable `home-manager` command without relying on nix profile subcommands.
  # Wrapper runs home-manager via `nix run`.

  local bin_dir="$HOME_DIR/.local/bin"
  mkdir -p "$bin_dir"

  cat > "$bin_dir/home-manager" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Ensure nix is available in non-login shells
if ! command -v nix >/dev/null 2>&1; then
  if [[ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  elif [[ -e /nix/var/nix/profiles/default/etc/profile.d/nix.sh ]]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix.sh
  elif [[ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
    # shellcheck disable=SC1091
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
  fi
fi

exec nix run github:nix-community/home-manager -- "$@"
EOF

  chmod +x "$bin_dir/home-manager"

  # Ensure ~/.local/bin is on PATH for login shells.
  # We do NOT replace the user's bash/zsh config; we add a small, idempotent snippet.
  local prof="$HOME_DIR/.profile"
  touch "$prof"
  if ! grep -q 'base-tooling:localbin' "$prof"; then
    cat >> "$prof" <<'EOF'

# base-tooling:localbin (ensure ~/.local/bin on PATH)
if [ -d "$HOME/.local/bin" ]; then
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH="$HOME/.local/bin:$PATH" ;;
  esac
fi
EOF
  fi

  msg "Linux: ensured 'home-manager' command via ~/.local/bin/home-manager"
}

apply_configuration() {
  msg "Applying declarative configuration..."
  export BASE_TOOLING_USER="$USERNAME"

  # Ensure nix available inside the script
  source_nix_profile_if_needed
  have nix || die "nix is not in PATH for this shell. Open a new terminal or ensure nix-daemon profile is sourced."

  if is_darwin; then
    require_sudo

    # Build system configuration (user context). --impure needed for BASE_TOOLING_USER via getEnv.
    nix build --impure "${INSTALL_DIR}#darwinConfigurations.${DARWIN_TARGET}.system" -L

    # Activate as root
    sudo "${INSTALL_DIR}/result/sw/bin/darwin-rebuild" switch --impure --flake "${INSTALL_DIR}#${DARWIN_TARGET}"
  else
    # Linux Home Manager configuration for "<user>@linux"
    nix run github:nix-community/home-manager -- \
      switch \
      --impure \
      --flake "${INSTALL_DIR}#${USERNAME}@linux"
  fi
}

#############################################
# main
#############################################
ensure_git
ensure_nix
source_nix_profile_if_needed
enable_flakes_idempotent
ensure_homebrew_darwin
ensure_repo

# OS-specific installs
install_rancher_desktop_linux
ensure_linux_zsh_default

apply_configuration

if is_linux; then
  ensure_home_manager_command
  msg "Open a NEW terminal (or run: source ~/.profile) so PATH updates take effect."
fi

msg "Done."
