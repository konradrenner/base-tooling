#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${HOME}/.base-tooling"
LINUX_HM_TARGET="konrad@linux"
DARWIN_TARGET="default"

is_linux()  { [ "$(uname -s)" = "Linux" ]; }
is_darwin() { [ "$(uname -s)" = "Darwin" ]; }


msg() { printf "\n==> %s\n" "$*"; }

UPDATE_RANCHER=0

usage() {
  cat <<'USAGE'
Usage: update.sh [--update-rancher] [--no-pull]

  --update-rancher   Update Rancher Desktop on Linux (downloads latest .deb/.rpm).
  --no-pull          Do not run git pull (useful if you are on a local branch).
USAGE
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
    | grep -Eo 'https://[^\"]+\.(deb|rpm)' \
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

main() {
  local no_pull=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --update-rancher) UPDATE_RANCHER=1; shift ;;
      --no-pull) no_pull=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option: $1"; usage; exit 2 ;;
    esac
  done

  if [ ! -d "${INSTALL_DIR}/.git" ]; then
    echo "ERROR: Repo not found at ${INSTALL_DIR}."
    echo "Run the Day-0 installer first."
    exit 1
  fi

  if [ "$no_pull" -eq 0 ]; then
    msg "Updating repo..."
    if [ -n "$(git -C "${INSTALL_DIR}" status --porcelain)" ]; then
      echo "ERROR: Working tree has uncommitted changes in ${INSTALL_DIR}."
      echo "Please commit/stash them, or re-run with --no-pull."
      exit 1
    fi
    git -C "${INSTALL_DIR}" pull --rebase
  else
    msg "Skipping git pull (--no-pull)."
  fi

  if [ "$UPDATE_RANCHER" -eq 1 ]; then
    update_rancher_desktop_linux
  fi

  msg "Applying configuration..."
  if is_darwin; then
    nix build "${INSTALL_DIR}#darwinConfigurations.${DARWIN_TARGET}.system"
    sudo ./result/sw/bin/darwin-rebuild switch --flake "${INSTALL_DIR}#${DARWIN_TARGET}"
  else
    nix run github:nix-community/home-manager -- switch --flake "${INSTALL_DIR}#${LINUX_HM_TARGET}"
  fi

  msg "Done."
}

main "$@"
