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
  update.sh --user <username> [--no-pull] [--dir <path>]

Required:
  --user <username>     Local account name (e.g. koni)

Optional:
  --no-pull             Do not run git pull (useful if you are on a local branch)
  --dir <path>          Repo directory (default: ~/.base-tooling)

Notes:
  - This script does NOT run 'nix flake update'. It only pulls the repo.
  - Lockfile updates are intended to be done manually by the platform team.
USAGE
}

USERNAME=""
NO_PULL=0

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --user) shift; USERNAME="${1:-}"; shift ;;
      --no-pull) NO_PULL=1; shift ;;
      --dir) shift; INSTALL_DIR="${1:-}"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
    esac
  done

  if [ -z "${USERNAME}" ]; then
    echo "ERROR: --user is required." >&2
    usage
    exit 2
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

update_rancher_linux_repo() {
  if ! is_linux; then
    return 0
  fi

  msg "Linux: Updating Rancher Desktop..."

  require_sudo

  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y
    sudo apt-get install -y rancher-desktop
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf makecache -y
    sudo dnf upgrade -y rancher-desktop || sudo dnf install -y rancher-desktop
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

  update_rancher_linux_repo

  apply_configuration
  msg "Done."
}

main "$@"
