#!/usr/bin/env bash
set -euo pipefail

# base-tooling update (Day-2)
# - Updates repo (pull latest)
# - Applies configuration (same as install)
# - Ensures bash on Linux picks up Nix + Home Manager env

SCRIPT_NAME="$(basename "$0")"
REPO_URL_DEFAULT="https://github.com/konradrenner/base-tooling.git"
INSTALL_DIR_DEFAULT="$HOME/.base-tooling"
DARWIN_TARGET_DEFAULT="default"

msg() { printf "\n==> %s\n" "$*"; }
warn() { printf "warning: %s\n" "$*" >&2; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

is_darwin() { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux()  { [[ "$(uname -s)" == "Linux"  ]]; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

require_sudo() {
  msg "Sudo privileges required. You may be prompted for your password."
  sudo -v
}

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME --user <username> [--dir <path>] [--no-pull] [--darwin-target <name>]

Examples:
  ./update.sh --user koni
  ./update.sh --user koni --no-pull
EOF
}

USERNAME=""
INSTALL_DIR="$INSTALL_DIR_DEFAULT"
DARWIN_TARGET="$DARWIN_TARGET_DEFAULT"
NO_PULL="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USERNAME="${2:-}"; shift 2;;
    --dir) INSTALL_DIR="${2:-}"; shift 2;;
    --darwin-target) DARWIN_TARGET="${2:-}"; shift 2;;
    --no-pull) NO_PULL="1"; shift;;
    -h|--help) usage; exit 0;;
    *) die "Unknown argument: $1";;
  esac
done

[[ -n "$USERNAME" ]] || { usage; die "--user is required"; }

msg "Base tooling update (Day-2) starting..."
msg "Detected OS: $(uname -s) ($(uname -m))"
msg "Using user: $USERNAME"
msg "Repo dir: $INSTALL_DIR"

need_cmd git
need_cmd nix

update_repo() {
  msg "Updating repo..."
  if [[ ! -d "$INSTALL_DIR/.git" ]]; then
    die "Repo not found at $INSTALL_DIR. Run install.sh first."
  fi

  if [[ "$NO_PULL" == "1" ]]; then
    msg "Skipping pull (--no-pull)."
    return 0
  fi

  # If there are local changes, don't destroy them. Just fetch and try ff-only merge.
  git -C "$INSTALL_DIR" fetch --all --prune
  if git -C "$INSTALL_DIR" merge --ff-only origin/main >/dev/null 2>&1; then
    msg "Updated to latest origin/main."
  else
    msg "Current branch already up to date (or local changes prevent fast-forward)."
  fi
}

ensure_bash_sees_nix_linux() {
  msg "Linux: Ensuring bash sees Nix + Home Manager environment (idempotent)."

  local bashrc="$HOME/.bashrc"
  touch "$bashrc"

  local begin="# >>> base-tooling: nix+home-manager >>>"

  if grep -qF "$begin" "$bashrc"; then
    msg "Linux: bash integration already present."
    return 0
  fi

  cat >>"$bashrc" <<'EOF'

# >>> base-tooling: nix+home-manager >>>
# Ensure Nix profile is available in interactive bash shells.
# (Does not change prompt/colors; only ensures PATH + env vars.)
if [ -e "/etc/profile.d/nix.sh" ]; then
  . "/etc/profile.d/nix.sh"
elif [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
  . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi

# Home Manager session vars (if present)
if [ -e "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
  . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
fi
# <<< base-tooling: nix+home-manager <<<
EOF

  msg "Linux: Added bash integration block to ~/.bashrc"
  msg "Open a NEW terminal (or run: source ~/.bashrc) so PATH updates take effect."
}

apply_configuration() {
  msg "Applying declarative configuration..."
  export BASE_TOOLING_USER="$USERNAME"

  if is_darwin; then
    require_sudo
    nix build --impure "${INSTALL_DIR}#darwinConfigurations.${DARWIN_TARGET}.system"
    sudo env BASE_TOOLING_USER="$USERNAME" ./result/sw/bin/darwin-rebuild switch --impure --flake "${INSTALL_DIR}#${DARWIN_TARGET}"
  elif is_linux; then
    nix run github:nix-community/home-manager -- \
      switch \
      -b before-hm \
      --impure \
      --flake "${INSTALL_DIR}#${USERNAME}@linux"
    ensure_bash_sees_nix_linux
  else
    die "Unsupported OS: $(uname -s)"
  fi
}

update_repo
apply_configuration

msg "Done."
