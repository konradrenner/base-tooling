#!/usr/bin/env bash
set -euo pipefail

# base-tooling update (Day-2)
# Usage:
#   ./update.sh --user <username> [--no-pull]

msg()  { printf '\n==> %s\n\n' "$*"; }
err()  { printf 'ERROR: %s\n' "$*" >&2; }

usage() {
  cat <<'USAGE'
Usage: update.sh --user <username> [--no-pull]

Options:
  --user <name>   Username to configure (required)
  --dir <path>    Repo directory (default: ~/.base-tooling)
  --no-pull       Do not git pull (useful when you have local changes)
  -h, --help      Show help
USAGE
}

is_darwin() { [[ "$(uname -s)" == "Darwin" ]]; }

require_sudo() {
  if ! sudo -n true 2>/dev/null; then
    msg "Sudo privileges required. You may be prompted for your password."
    sudo true
  fi
}

ensure_home_manager_cli() {
  if command -v home-manager >/dev/null 2>&1; then
    return
  fi
  msg "Ensuring home-manager CLI is installed (nix profile)."
  nix profile install \
    --extra-experimental-features nix-command \
    --extra-experimental-features flakes \
    github:nix-community/home-manager
}

ensure_linux_bash_integration() {
  local snippet_dir="$HOME/.config/base-tooling"
  local snippet_file="$snippet_dir/bashrc.snippet"
  mkdir -p "$snippet_dir"

  cat > "$snippet_file" <<'SNIPPET'
# --- base-tooling (managed) ---
if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
elif [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
  # shellcheck disable=SC1091
  . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi

if [ -e "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
  # shellcheck disable=SC1091
  . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
fi
# --- /base-tooling (managed) ---
SNIPPET

  local bashrc="$HOME/.bashrc"
  touch "$bashrc"
  local marker="# base-tooling: source managed snippet"
  if ! grep -Fq "$marker" "$bashrc"; then
    {
      echo
      echo "$marker"
      echo "[ -f \"$snippet_file\" ] && . \"$snippet_file\""
    } >> "$bashrc"
  fi
}

apply_configuration() {
  msg "Applying declarative configuration..."
  export BASE_TOOLING_USER="$USERNAME"

  if is_darwin; then
    require_sudo
    nix build --impure "$INSTALL_DIR#darwinConfigurations.${DARWIN_TARGET}.system"
    sudo --preserve-env=BASE_TOOLING_USER ./result/sw/bin/darwin-rebuild switch --impure --flake "$INSTALL_DIR#${DARWIN_TARGET}"
    ensure_home_manager_cli
  else
    nix run github:nix-community/home-manager -- \
      switch \
      --impure \
      --flake "$INSTALL_DIR#${USERNAME}@linux" \
      -b backup

    ensure_home_manager_cli
    ensure_linux_bash_integration

    msg "Linux: Open a NEW terminal (or run: source ~/.bashrc) so PATH updates take effect."
  fi
}

USERNAME=""
INSTALL_DIR="${HOME}/.base-tooling"
DARWIN_TARGET="default"
NO_PULL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      USERNAME="$2"; shift 2;;
    --dir)
      INSTALL_DIR="$2"; shift 2;;
    --no-pull)
      NO_PULL=1; shift;;
    -h|--help)
      usage; exit 0;;
    *)
      err "Unknown argument: $1"; usage; exit 1;;
  esac
done

if [[ -z "$USERNAME" ]]; then
  err "--user is required"; usage; exit 1
fi

msg "Base tooling update (Day-2) starting..."
msg "Using user: $USERNAME"
msg "Repo dir: $INSTALL_DIR"

if [[ ! -d "$INSTALL_DIR/.git" ]]; then
  err "Repo not found at $INSTALL_DIR. Run install.sh first."; exit 1
fi

msg "Updating repo..."
if [[ "$NO_PULL" -eq 1 ]]; then
  msg "--no-pull set; skipping git pull."
else
  # Avoid failing on local changes: keep it simple and informative.
  if ! git -C "$INSTALL_DIR" diff --quiet || ! git -C "$INSTALL_DIR" diff --cached --quiet; then
    err "Working tree has uncommitted changes in $INSTALL_DIR. Commit/stash them, or re-run with --no-pull."; exit 1
  fi
  git -C "$INSTALL_DIR" pull --ff-only
fi

apply_configuration

msg "Done."
