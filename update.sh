#!/usr/bin/env bash
set -euo pipefail

# base-tooling update (Day-2)
# - pulls latest repo (unless --no-pull)
# - applies configuration (nix-darwin on macOS / Home Manager on Linux)
# - on Linux: keeps zsh as default for your user

msg() { printf "\n==> %s\n" "$*"; }
warn() { printf "\nWARN: %s\n" "$*" >&2; }
die() { printf "\nERROR: %s\n" "$*" >&2; exit 1; }

is_darwin() { [ "$(uname -s)" = "Darwin" ]; }
is_linux()  { [ "$(uname -s)" = "Linux" ]; }

require_sudo() {
  if sudo -n true 2>/dev/null; then
    return
  fi
  msg "Sudo privileges required. You may be prompted for your password."
  sudo true
}

usage() {
  cat <<'EOF'
Usage: update.sh --user <name> [--dir <path>] [--no-pull]

Options:
  --user <name>   Username used inside the flake (BASE_TOOLING_USER)
  --dir  <path>   Repo directory (default: ~/.base-tooling)
  --no-pull       Do not git pull/fetch/reset; only apply configuration
EOF
}

USERNAME=""
INSTALL_DIR="${BASE_TOOLING_DIR:-$HOME/.base-tooling}"
NO_PULL="false"

while [ "${1:-}" != "" ]; do
  case "$1" in
    --user) USERNAME="${2:-}"; shift 2;;
    --dir)  INSTALL_DIR="${2:-}"; shift 2;;
    --no-pull) NO_PULL="true"; shift 1;;
    -h|--help) usage; exit 0;;
    *) die "Unknown argument: $1";;
  esac
done

[ -n "$USERNAME" ] || { usage; die "--user is required"; }

ensure_repo_clean_or_no_pull() {
  if [ "$NO_PULL" = "true" ]; then
    return
  fi
  if [ ! -d "$INSTALL_DIR/.git" ]; then
    die "Repo not found at $INSTALL_DIR. Run install.sh first."
  fi
  if ! git -C "$INSTALL_DIR" diff --quiet || ! git -C "$INSTALL_DIR" diff --cached --quiet; then
    die "Working tree has uncommitted changes in $INSTALL_DIR. Commit/stash them, or re-run with --no-pull."
  fi
}

update_repo() {
  if [ "$NO_PULL" = "true" ]; then
    msg "Skipping repo update (--no-pull)."
    return
  fi
  msg "Updating repo..."
  git -C "$INSTALL_DIR" fetch --prune origin
  git -C "$INSTALL_DIR" reset --hard origin/main
  msg "Current branch main is up to date."
}

ensure_nix_profile_add_wrapper() {
  if ! is_linux; then
    return
  fi
  if nix profile add --help >/dev/null 2>&1; then
    return
  fi

  msg "Linux: Installing Nix compatibility wrapper for 'nix profile add' (idempotent)."
  mkdir -p "$HOME/.local/bin"

  local real_nix=""
  if [ -x /nix/var/nix/profiles/default/bin/nix ]; then
    real_nix="/nix/var/nix/profiles/default/bin/nix"
  elif [ -x "$HOME/.nix-profile/bin/nix" ]; then
    real_nix="$HOME/.nix-profile/bin/nix"
  else
    real_nix="$(command -v nix || true)"
  fi
  [ -n "$real_nix" ] && [ -x "$real_nix" ] || die "Could not find a working nix binary."

  cat > "$HOME/.local/bin/nix" <<EOF
#!/usr/bin/env bash
set -euo pipefail
REAL_NIX="${real_nix}"

if [ "\${#}" -ge 2 ] && [ "\${1}" = "profile" ] && [ "\${2}" = "add" ]; then
  shift 2
  exec "\$REAL_NIX" profile install "\$@"
fi

exec "\$REAL_NIX" "\$@"
EOF
  chmod +x "$HOME/.local/bin/nix"
  export PATH="$HOME/.local/bin:$PATH"
}

ensure_home_manager_cli() {
  if command -v home-manager >/dev/null 2>&1; then
    return
  fi
  msg "Ensuring home-manager CLI is installed (nix profile install)."
  ensure_nix_profile_add_wrapper
  nix profile install \
    --extra-experimental-features nix-command \
    --extra-experimental-features flakes \
    github:nix-community/home-manager
}

ensure_linux_zsh_system() {
  if ! is_linux; then return; fi
  if [ -x /usr/bin/zsh ]; then return; fi
  msg "Linux: Installing system zsh (apt)..."
  require_sudo
  sudo apt-get update -y
  sudo apt-get install -y zsh
}

set_default_shell_zsh() {
  if ! is_linux; then return; fi
  ensure_linux_zsh_system

  if ! grep -q '^/usr/bin/zsh$' /etc/shells 2>/dev/null; then
    require_sudo
    echo "/usr/bin/zsh" | sudo tee -a /etc/shells >/dev/null
  fi

  local current_shell
  current_shell="$(getent passwd "$USERNAME" | cut -d: -f7 || true)"
  if [ "$current_shell" = "/usr/bin/zsh" ]; then
    return
  fi

  msg "Linux: Setting default shell for '$USERNAME' to /usr/bin/zsh"
  require_sudo
  sudo chsh -s /usr/bin/zsh "$USERNAME" || warn "Could not change shell automatically. Run: chsh -s /usr/bin/zsh"
}

apply_configuration() {
  msg "Applying declarative configuration..."
  export BASE_TOOLING_USER="$USERNAME"

  if is_darwin; then
    require_sudo
    nix build --impure "${INSTALL_DIR}#darwinConfigurations.default.system"
    sudo ./result/sw/bin/darwin-rebuild switch --impure --flake "${INSTALL_DIR}#default"
  else
    ensure_nix_profile_add_wrapper
    ensure_home_manager_cli

    msg "Starting Home Manager activation"
    nix run \
      --extra-experimental-features nix-command \
      --extra-experimental-features flakes \
      github:nix-community/home-manager -- \
      switch \
      -b before-hm \
      --impure \
      --flake "${INSTALL_DIR}#${USERNAME}@linux"

    set_default_shell_zsh
  fi
}

main() {
  msg "Base tooling update (Day-2) starting..."
  msg "Detected OS: $(uname -s) ($(uname -m))"
  msg "Using user: $USERNAME"
  msg "Repo dir: $INSTALL_DIR"

  ensure_repo_clean_or_no_pull
  update_repo
  apply_configuration

  msg "Done."
  if is_linux; then
    msg "Open a NEW terminal so your login shell (zsh) is used."
  fi
}

main "$@"
