#!/usr/bin/env bash
set -euo pipefail
trap 'echo "ERROR: install.sh failed at line $LINENO." >&2' ERR

# --------- config ----------
REPO_URL="https://github.com/konradrenner/base-tooling.git"
DEFAULT_INSTALL_DIR="${HOME}/.base-tooling"
DARWIN_TARGET="default"
# ---------------------------

is_linux()  { [ "$(uname -s)" = "Linux" ]; }
is_darwin() { [ "$(uname -s)" = "Darwin" ]; }

msg() { printf "\n==> %s\n" "$*"; }

require_cmd() {
  local c="$1"
  if ! command -v "$c" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $c" >&2
    exit 1
  fi
}

require_sudo() {
  require_cmd sudo
  if ! sudo -n true 2>/dev/null; then
    echo "Sudo privileges required. You may be prompted for your password."
    sudo true
  fi
}

usage() {
  cat <<'USAGE'
Usage:
  install.sh --user <username> [--dir <path>] [--no-clone]

Required:
  --user <username>   Local account name (e.g. koni)

Optional:
  --dir <path>        Install/checkout directory (default: ~/.base-tooling)
  --no-clone          Do not clone/fetch; use current directory as repo
                      (useful for local development)

Examples:
  ./install.sh --user koni
  ./install.sh --user koni --dir ~/.base-tooling

  # Day-0 from a completely new machine (no git clone required):
  curl -fsSL https://raw.githubusercontent.com/konradrenner/base-tooling/main/install.sh | bash -s -- --user koni
USAGE
}

USERNAME=""
INSTALL_DIR="${DEFAULT_INSTALL_DIR}"
NO_CLONE=0

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --user)
        shift
        USERNAME="${1:-}"
        shift
        ;;
      --dir)
        shift
        INSTALL_DIR="${1:-}"
        shift
        ;;
      --no-clone)
        NO_CLONE=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage
        exit 2
        ;;
    esac
  done

  if [ -z "${USERNAME}" ]; then
    echo "ERROR: --user is required." >&2
    usage
    exit 2
  fi
}

ensure_nix() {
  if command -v nix >/dev/null 2>&1; then
    msg "Nix already installed."
    return 0
  fi

  msg "Installing Nix (Determinate Systems installer)..."
  require_cmd curl
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install

  # best-effort load for current shell
  if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi

  require_cmd nix
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
  require_cmd curl
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Ensure brew is in PATH for this script run (Apple Silicon default location)
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi

  require_cmd brew
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
  require_cmd curl

  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64) arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
  esac

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

  msg "Rancher Desktop installed. Start it once and select 'dockerd (moby)' for VS Code Dev Containers."
}

ensure_git() {
  if command -v git >/dev/null 2>&1; then
    msg "git already installed."
    return 0
  fi

  if is_darwin; then
    msg "git not found. Installing Xcode Command Line Tools (interactive prompt may appear)..."
    xcode-select --install || true
    echo "After CLT install finishes, re-run this install command." >&2
    exit 1
  fi

  msg "git not found. Installing via package manager..."
  require_sudo

  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update && sudo apt-get install -y git
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y git
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --noconfirm git
  else
    echo "ERROR: cannot install git automatically on this Linux." >&2
    echo "Install git manually and re-run." >&2
    exit 1
  fi
}

clone_or_update_repo() {
  if [ "$NO_CLONE" -eq 1 ]; then
    msg "--no-clone set: using current directory as repo"
    INSTALL_DIR="$(pwd)"
    return 0
  fi

  msg "Ensuring repo is present at: ${INSTALL_DIR}"
  if [ -d "${INSTALL_DIR}/.git" ]; then
    msg "Repo already cloned. Fetching latest..."
    git -C "${INSTALL_DIR}" fetch --all --prune
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

    # Always run from repo dir so relative paths are stable (result link etc.)
    cd "${INSTALL_DIR}"

    # Build system configuration (user context). --impure needed for BASE_TOOLING_USER via getEnv.
    BASE_TOOLING_USER="${USERNAME}" \
      nix build --impure \
      --out-link "${INSTALL_DIR}/result" \
      "${INSTALL_DIR}#darwinConfigurations.${DARWIN_TARGET}.system"

    # Activate as root (ensure BASE_TOOLING_USER is visible under sudo)
    sudo env BASE_TOOLING_USER="${USERNAME}" \
      "${INSTALL_DIR}/result/sw/bin/darwin-rebuild" switch \
      --impure \
      --flake "${INSTALL_DIR}#${DARWIN_TARGET}"

  else
    cd "${INSTALL_DIR}"

    # Linux Home Manager configuration for "<user>@linux"
    BASE_TOOLING_USER="${USERNAME}" \
      nix run github:nix-community/home-manager -- \
        switch \
        --impure \
        --flake "${INSTALL_DIR}#${USERNAME}@linux"
  fi
}

install_rancher_linux() {
  if [ "$(uname -s)" != "Linux" ]; then
    return 0
  fi

  if command -v rancher-desktop >/dev/null 2>&1; then
    msg "Rancher Desktop already installed."
    return 0
  fi

  msg "Linux: Installing Rancher Desktop from upstream release (.deb/.rpm)..."

  require_cmd curl
  require_sudo

  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64)
      ARCH="x86_64"
      ;;
    aarch64|arm64)
      ARCH="arm64"
      ;;
    *)
      echo "Unsupported architecture: $ARCH"
      exit 1
      ;;
  esac

  CACHE_DIR="${HOME}/.cache/base-tooling"
  mkdir -p "${CACHE_DIR}"

  # Get latest release tag
  TAG="$(curl -fsSL https://api.github.com/repos/rancher-sandbox/rancher-desktop/releases/latest \
    | grep -m1 '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')"

  if [ -z "$TAG" ]; then
    echo "Failed to determine latest Rancher Desktop release."
    exit 1
  fi

  if command -v apt-get >/dev/null 2>&1; then
    FILE="rancher-desktop-${TAG#v}-linux-${ARCH}.deb"
    URL="https://github.com/rancher-sandbox/rancher-desktop/releases/download/${TAG}/${FILE}"

    msg "Downloading ${FILE}..."
    curl -fL "$URL" -o "${CACHE_DIR}/${FILE}"

    msg "Installing via apt..."
    sudo apt install -y "${CACHE_DIR}/${FILE}"

  elif command -v dnf >/dev/null 2>&1; then
    FILE="rancher-desktop-${TAG#v}-linux-${ARCH}.rpm"
    URL="https://github.com/rancher-sandbox/rancher-desktop/releases/download/${TAG}/${FILE}"

    msg "Downloading ${FILE}..."
    curl -fL "$URL" -o "${CACHE_DIR}/${FILE}"

    msg "Installing via dnf..."
    sudo dnf install -y "${CACHE_DIR}/${FILE}"

  else
    echo "Unsupported package manager (only apt & dnf supported)."
    exit 1
  fi

  msg "Rancher Desktop installed successfully."
}

main() {
  parse_args "$@"

  msg "Base tooling install (Day-0) starting..."
  msg "Detected OS: $(uname -s) ($(uname -m))"
  msg "Using user: ${USERNAME}"
  msg "Repo dir: ${INSTALL_DIR}"

  require_cmd curl

  ensure_nix
  enable_flakes

  # macOS: Rancher Desktop installed declaratively via nix-darwin Homebrew cask (brew must exist)
  ensure_homebrew_darwin

  # Linux: install Rancher Desktop via upstream package (optional but default)
  install_rancher_desktop_linux

  ensure_git
  clone_or_update_repo

  install_rancher_linux

  apply_configuration

  msg "Done."
  echo "Next:"
  echo " - Open a new terminal."
  echo " - Start Rancher Desktop. Choose 'dockerd (moby)' for VS Code Dev Containers."
  echo " - Day-2 updates: ${INSTALL_DIR}/update.sh --user ${USERNAME}"
}

main "$@"
