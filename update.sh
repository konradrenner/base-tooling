#!/usr/bin/env bash
set -euo pipefail

# base-tooling update (Day-2)
# - pulls latest changes (optional)
# - applies nix-darwin / home-manager
# - re-applies bash env snippet on Linux (in case user restored dotfiles)

msg() { printf "\n==> %s\n" "$*"; }
err() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

is_darwin() { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux()  { [[ "$(uname -s)" == "Linux" ]]; }
arch() { uname -m; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || err "Missing command: $1"; }

require_sudo() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    msg "Sudo privileges required. You may be prompted for your password."
    sudo -v
  fi
}

USERNAME=""
NO_PULL="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USERNAME="${2:-}"; shift 2;;
    --no-pull) NO_PULL="1"; shift;;
    -h|--help)
      cat <<'USAGE'
Usage: update.sh --user <name> [--no-pull]
USAGE
      exit 0
      ;;
    *) err "Unknown argument: $1";;
  esac
done

[[ -n "$USERNAME" ]] || err "--user is required"

INSTALL_DIR="${HOME}/.base-tooling"
DARWIN_TARGET="default"

BT_BEGIN="# >>> base-tooling (managed) >>>"
BT_END="# <<< base-tooling (managed) <<<"

strip_block() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  awk -v b="$BT_BEGIN" -v e="$BT_END" '
    $0==b {in=1; next}
    $0==e {in=0; next}
    !in {print}
  ' "$file" > "${file}.bt_tmp"
  mv "${file}.bt_tmp" "$file"
}

append_block() {
  local file="$1"
  local content="$2"
  mkdir -p "$(dirname "$file")" 2>/dev/null || true
  touch "$file"
  strip_block "$file"
  {
    printf "\n%s\n" "$BT_BEGIN"
    printf "%s\n" "$content"
    printf "%s\n" "$BT_END"
  } >> "$file"
}

linux_bash_env_block() {
  cat <<'EOF'
# Nix (multi-user + single-user)
if [ -r "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
  . "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
fi
if [ -r "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
  . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi

# Home Manager session vars (puts HM packages into PATH, exports vars, etc.)
if [ -r "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
  . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
fi

# Safety: ensure common profile bins are on PATH even if dotfiles were restored
case ":$PATH:" in
  *":$HOME/.nix-profile/bin:"*) ;;
  *) export PATH="$HOME/.nix-profile/bin:$PATH" ;;
esac
case ":$PATH:" in
  *":/nix/var/nix/profiles/default/bin:"*) ;;
  *) export PATH="/nix/var/nix/profiles/default/bin:$PATH" ;;
esac
EOF
}

ensure_linux_shell_env() {
  [[ "$(uname -s)" == "Linux" ]] || return 0
  msg "Linux: Ensuring bash sees Nix + Home Manager environment (idempotent)."
  local block; block="$(linux_bash_env_block)"
  append_block "${HOME}/.profile" "$block"
  append_block "${HOME}/.bashrc" "$block"
}

update_repo() {
  msg "Updating repo..."
  [[ -d "${INSTALL_DIR}/.git" ]] || err "Repo not found at ${INSTALL_DIR}. Run install.sh first."
  if [[ "$NO_PULL" == "1" ]]; then
    msg "Skipping pull (--no-pull)."
    return 0
  fi
  git -C "$INSTALL_DIR" fetch --all --prune
  git -C "$INSTALL_DIR" pull --ff-only || msg "Note: fast-forward pull not possible (local commits/changes?). Continuing."
}

apply_configuration() {
  msg "Applying declarative configuration..."
  export BASE_TOOLING_USER="${USERNAME}"

  if is_darwin; then
    require_sudo
    nix build --impure "${INSTALL_DIR}#darwinConfigurations.${DARWIN_TARGET}.system" -L
    sudo ./result/sw/bin/darwin-rebuild switch --impure --flake "${INSTALL_DIR}#${DARWIN_TARGET}" -L
  else
    nix run github:nix-community/home-manager -- \
      switch \
      -b before-hm \
      --impure \
      --flake "${INSTALL_DIR}#${USERNAME}@linux"
  fi
}

main() {
  msg "Base tooling update (Day-2) starting..."
  msg "Detected OS: $(uname -s) ($(arch))"
  msg "Using user: ${USERNAME}"
  msg "Repo dir: ${INSTALL_DIR}"

  require_cmd git
  require_cmd nix

  update_repo
  apply_configuration
  ensure_linux_shell_env

  msg "Done."
  if is_linux; then
    msg "Open a NEW terminal (or run: source ~/.bashrc) so PATH updates take effect."
  fi
}

main "$@"
