#!/usr/bin/env bash
set -euo pipefail

# Fail with readable message
trap 'echo "ERROR: Script failed at line $LINENO."' ERR

# --------- config ----------
REPO_URL="https://github.com/konradrenner/base-tooling.git"
INSTALL_DIR="${HOME}/.base-tooling"
LINUX_HM_TARGET="konrad@linux"
DARWIN_TARGET="default"
# ---------------------------

is_linux()  { [ "$(uname -s)" = "Linux" ]; }
is_darwin() { [ "$(uname -s)" = "Darwin" ]; }

msg() { printf "\n==> %s\n" "$*"; }

require_sudo() {
  if ! command -v sudo >/dev/null 2>&1; then
    echo "ERROR: sudo is required but not installed."
    exit 1
  fi

  if ! sudo -n true 2>/dev/null; then
    echo "Sudo privileges required. You may be prompted for your password."
    sudo true
  fi
}

ensure_nix() {
  if command -v nix >/dev/null 2>&1; then
    msg "Nix already installed."
    return 0
  fi

  msg "Installing Nix (Determinate Systems installer)..."
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install

  # best-effort load for current shell
  if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
}

enable_flakes() {
  msg "Enabling nix-command + flakes (idempotent)."
  mkdir -p ~/.config/nix
  if [ ! -f ~/.config/nix/nix.conf ]; then
    cat > ~/.config/nix/nix.conf <<'EOF'
experimental-features = nix-command flakes
EOF
    return 0
  fi

  if ! grep -q "experimental-features" ~/.config/nix/nix.conf; then
    echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
  elif ! grep -q "flakes" ~/.config/nix/nix.conf; then
    # If experimental-features exists but flakes missing, append a safe line.
    echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
  fi
}

ensure_homebrew_darwin() {
  if ! is_darwin; then return 0; fi

  # nix-darwin can manage Homebrew packages declaratively, but Homebrew itself must exist.
  if command -v brew >/dev/null 2>&1; then
    msg "Homebrew already installed."
    return 0
  fi

  msg "Homebrew not found. Installing Homebrew (required for Rancher Desktop cask on macOS)..."
  # Official Homebrew installer (interactive prompts may appear)
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Ensure brew is in PATH for this script run (Apple Silicon default location)
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
}

install_rancher_desktop_linux() {
  if ! is_linux; then return 0; fi

  msg "Linux: Installing Rancher Desktop from upstream release (.deb/.rpm) if missing..."
  if command -v rancher-desktop >/dev/null 2>&1; then
    msg "Rancher Desktop already installed."
    return 0
  fi

  local pkgtype=""
  if command -v apt-get >/dev/null 2>&1; then
    pkgtype="deb"
  elif command -v dnf >/dev/null 2>&1 || command -v rpm >/dev/null 2>&1; then
    pkgtype="rpm"
  else
    msg "No supported package manager found (need apt or rpm). Skipping Rancher Desktop install."
    return 0
  fi

  require_sudo

  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64) arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
  esac

  # Get latest release tag + matching asset via GitHub API
  local tag asset_url
  tag="$(curl -fsSL https://api.github.com/repos/rancher-sandbox/rancher-desktop/releases/latest \
    | grep -m1 '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')"

  asset_url="$(curl -fsSL "https://api.github.com/repos/rancher-sandbox/rancher-desktop/releases/tags/${tag}" \
    | grep -Eo 'https://[^"]+\.(deb|rpm)' \
    | grep -E "${pkgtype}$" \
    | grep -E "${arch}" \
    | head -n1)"

  if [ -z "$asset_url" ]; then
    msg "Could not find matching ${pkgtype} asset for arch ${arch}. Skipping."
    return 0
  fi

  local tmp pkg
  tmp="$(mktemp -d)"
  pkg="${tmp}/rancher-desktop.${pkgtype}"
  curl -fsSL "$asset_url" -o "$pkg"

  if [ "$pkgtype" = "deb" ]; then
    sudo apt-get update
    sudo apt-get install -y "$pkg"
  else
    if command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y "$pkg"
    else
      sudo rpm -Uvh --replacepkgs "$pkg"
    fi
  fi

  msg "Rancher Desktop installed. Start it once and select 'dockerd (moby)' as engine for Dev Containers."
}

clone_or_update_repo() {
  msg "Ensuring repo is present at: ${INSTALL_DIR}"
  if [ -d "${INSTALL_DIR}/.git" ]; then
    msg "Repo already cloned. Fetching latest..."
    git -C "${INSTALL_DIR}" fetch --all --prune
    # Don't force merge here; day-2 update.sh does pull explicitly.
  else
    msg "Cloning ${REPO_URL} ..."
    mkdir -p "$(dirname "${INSTALL_DIR}")"
    git clone "${REPO_URL}" "${INSTALL_DIR}"
  fi
}

apply_configuration() {
  msg "Applying declarative configuration..."
  if is_darwin; then
    require_sudo
    # This expects: darwinConfigurations.default in flake.nix
    nix build "${INSTALL_DIR}#darwinConfigurations.${DARWIN_TARGET}.system"
    sudo ./result/sw/bin/darwin-rebuild switch --flake "${INSTALL_DIR}#${DARWIN_TARGET}"
  else
    # This expects: homeConfigurations."konrad@linux" in flake.nix
    nix run github:nix-community/home-manager -- switch --flake "${INSTALL_DIR}#${LINUX_HM_TARGET}"
  fi
}

main() {
  msg "Base tooling install (Day-0) starting..."
  msg "Detected OS: $(uname -s) ($(uname -m))"

  # curl and git are typically present; if git isn't, this setup can't proceed cleanly.
  if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR: curl is required but not found."
    echo "Please install curl via system package manager and re-run."
    exit 1
  fi

  ensure_nix
  enable_flakes
  ensure_homebrew_darwin

  # macOS: Rancher Desktop is installed declaratively via nix-darwin Homebrew (in your darwin module)
  install_rancher_desktop_linux

  # We need git to clone; on macOS this may trigger Xcode CLT prompt if missing
  if ! command -v git >/dev/null 2>&1; then
    if is_darwin; then
      msg "git not found. Installing Xcode Command Line Tools (interactive prompt may appear)..."
      xcode-select --install || true
      msg "After CLT install finishes, re-run this install command."
      exit 1
    else
      msg "git not found. Installing via package manager..."
      require_sudo
      if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y git
      elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y git
      elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm git
      else
        echo "ERROR: cannot install git automatically on this Linux."
        echo "Install git manually and re-run."
        exit 1
      fi
    fi
  fi

  clone_or_update_repo
  apply_configuration

  msg "Done."
  echo "Next:"
  echo " - Open a new terminal."
  echo " - On macOS, the first nix-darwin switch may ask for sudo."
  echo " - Start Rancher Desktop (Linux/macOS). In settings choose 'dockerd (moby)' for VS Code Dev Containers."
  echo " - Day-2 updates: ${INSTALL_DIR}/update.sh"
}

main "$@"
