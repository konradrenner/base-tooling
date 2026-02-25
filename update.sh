#!/usr/bin/env bash
set -euo pipefail
trap 'echo "ERROR: update.sh failed at line $LINENO." >&2' ERR

INSTALL_DIR="${HOME}/.base-tooling"
DARWIN_TARGET="default"

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
  update.sh --user <username> [--update-rancher] [--no-pull] [--dir <path>]

Required:
  --user <username>     Local account name (e.g. koni)

Optional:
  --update-rancher      (Linux) Update Rancher Desktop to latest release (.deb/.rpm)
  --no-pull             Do not run git pull (useful if you have local changes)
  --dir <path>          Repo directory (default: ~/.base-tooling)

Notes:
  - This script will NOT update flake.lock. It builds with --no-write-lock-file.
  - flake.lock updates should be done manually (platform team), committed, and pushed.

Examples:
  ~/.base-tooling/update.sh --user koni
  ~/.base-tooling/update.sh --user koni --no-pull
USAGE
}

USERNAME=""
UPDATE_RANCHER=0
NO_PULL=0

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --user)
        shift
        USERNAME="${1:-}"
        shift
        ;;
      --update-rancher)
        UPDATE_RANCHER=1
        shift
        ;;
      --no-pull)
        NO_PULL=1
        shift
        ;;
      --dir)
        shift
        INSTALL_DIR="${1:-}"
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

update_rancher_desktop_linux() {
  if ! is_linux; then return 0; fi

  if ! command -v rancher-desktop >/dev/null 2>&1; then
    msg "Rancher Desktop not found; skipping update."
    return 0
  fi

  local pkgtype=""
  if command -v apt-get >/dev/null 2>&1; then
    pkgtype="deb"
  elif command -v dnf >/dev/null 2>&1 || command -v rpm >/dev/null 2>&1; then
    pkgtype="rpm"
  else
    msg "No supported package manager found (need apt or rpm). Skipping Rancher Desktop update."
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

  msg "Checking latest Rancher Desktop release..."
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

  msg "Updating Rancher Desktop to ${tag}..."
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
}

apply_configuration() {
  msg "Applying declarative configuration..."
  require_cmd nix

  # Always put the build output link into the repo dir, not the current working directory.
  local out_link="${INSTALL_DIR}/result"

  if is_darwin; then
    require_sudo

    # Build in user context; DO NOT write flake.lock.
    BASE_TOOLING_USER="${USERNAME}" \
      nix build --impure --no-write-lock-file \
      --out-link "${out_link}" \
      "${INSTALL_DIR}#darwinConfigurations.${DARWIN_TARGET}.system"

    # Activate as root; preserve BASE_TOOLING_USER; also do not write lock file.
    sudo env BASE_TOOLING_USER="${USERNAME}" \
      "${out_link}/sw/bin/darwin-rebuild" switch \
      --impure --flake "${INSTALL_DIR}#${DARWIN_TARGET}" \
      --no-write-lock-file
  else
    # Linux Home Manager configuration for "<user>@linux"; DO NOT write flake.lock.
    BASE_TOOLING_USER="${USERNAME}" \
      nix run --no-write-lock-file github:nix-community/home-manager -- \
        switch \
        --impure \
        --flake "${INSTALL_DIR}#${USERNAME}@linux"
  fi
}

main() {
  parse_args "$@"

  msg "Base tooling update (Day-2) starting..."
  msg "Detected OS: $(uname -s) ($(uname -m))"
  msg "Using user: ${USERNAME}"
  msg "Repo dir: ${INSTALL_DIR}"

  if [ ! -d "${INSTALL_DIR}/.git" ]; then
    echo "ERROR: Repo not found at ${INSTALL_DIR}." >&2
    echo "Run install.sh first (Day-0)." >&2
    exit 1
  fi

  require_cmd git

  if [ "$NO_PULL" -eq 0 ]; then
    msg "Updating repo..."
    if [ -n "$(git -C "${INSTALL_DIR}" status --porcelain)" ]; then
      echo "ERROR: Working tree has uncommitted changes in ${INSTALL_DIR}." >&2
      echo "Commit/stash them, or re-run with --no-pull." >&2
      exit 1
    fi
    git -C "${INSTALL_DIR}" pull --rebase
  else
    msg "Skipping git pull (--no-pull)."
  fi

  if [ "$UPDATE_RANCHER" -eq 1 ]; then
    update_rancher_desktop_linux
  fi

  apply_configuration

  msg "Done."
}

main "$@"
