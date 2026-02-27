#!/usr/bin/env bash
set -euo pipefail

msg() { printf "\n==> %s\n" "$*"; }
err() { printf "\nERROR: %s\n" "$*" >&2; exit 1; }

USERNAME=""
INSTALL_DIR="${HOME}/.base-tooling"
NO_PULL="false"
DARWIN_TARGET="default"

usage() {
  cat <<'USAGE'
Usage:
  update.sh --user <name> [--dir <path>] [--no-pull] [--darwin-target <name>]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USERNAME="${2:-}"; shift 2 ;;
    --dir) INSTALL_DIR="${2:-}"; shift 2 ;;
    --no-pull) NO_PULL="true"; shift ;;
    --darwin-target) DARWIN_TARGET="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown argument: $1" ;;
  esac
done

[[ -n "$USERNAME" ]] || err "Missing --user <name>"

is_darwin() { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux() { [[ "$(uname -s)" == "Linux" ]]; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || return 1; }

ensure_sudo() {
  msg "Sudo privileges required. You may be prompted for your password."
  sudo -v
}

ensure_nix_loaded() {
  if require_cmd nix; then return; fi

  # best-effort load (for weird non-login shells)
  if [[ -e "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]]; then
    # shellcheck disable=SC1091
    . "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
  elif [[ -e "${HOME}/.nix-profile/etc/profile.d/nix.sh" ]]; then
    # shellcheck disable=SC1091
    . "${HOME}/.nix-profile/etc/profile.d/nix.sh"
  fi

  require_cmd nix || err "nix not found. Install Nix first (install.sh), or open a new terminal."
}


update_repo() {
  msg "Updating repo..."
  [[ -d "${INSTALL_DIR}/.git" ]] || err "Repo not found at ${INSTALL_DIR}. Run install.sh first."

  if [[ "$NO_PULL" == "true" ]]; then
    msg "--no-pull set; skipping git pull."
    return
  fi

  git -C "$INSTALL_DIR" pull --ff-only
}

apply_configuration() {
  msg "Applying declarative configuration..."
  export BASE_TOOLING_USER="${USERNAME}"

  if is_darwin; then
    ensure_sudo
    local out="/tmp/base-tooling-darwin-system"
    rm -f "$out" 2>/dev/null || true

    nix build --impure -L -o "$out" "${INSTALL_DIR}#darwinConfigurations.${DARWIN_TARGET}.system"
    sudo BASE_TOOLING_USER="${USERNAME}" "$out/sw/bin/darwin-rebuild" switch --impure --flake "${INSTALL_DIR}#${DARWIN_TARGET}"

  elif is_linux; then
    nix run github:nix-community/home-manager -- \
      switch \
      -b backup \
      --impure \
      --flake "${INSTALL_DIR}#${USERNAME}@linux"
  else
    err "Unsupported OS: $(uname -s)"
  fi
}

msg "Base tooling update (Day-2) starting..."
msg "Detected OS: $(uname -s) ($(uname -m))"
msg "Using user: ${USERNAME}"
msg "Repo dir: ${INSTALL_DIR}"

ensure_nix_loaded
update_repo
apply_configuration

msg "Done."
msg "Open a NEW terminal so your login shell/env is refreshed."
