#!/usr/bin/env bash
set -euo pipefail

msg() { echo -e "\n==> $*"; }
warn() { echo -e "WARN: $*" >&2; }
die() { echo -e "ERROR: $*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }
is_darwin() { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux()  { [[ "$(uname -s)" == "Linux"  ]]; }

require_sudo() { msg "Sudo privileges required. You may be prompted for your password."; sudo -v; }

usage() {
  cat <<'EOF'
Usage:
  update.sh --user <name> [--dir <path>] [--no-pull]

EOF
}

USERNAME=""
INSTALL_DIR=""
NO_PULL="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USERNAME="${2:-}"; shift 2 ;;
    --dir) INSTALL_DIR="${2:-}"; shift 2 ;;
    --no-pull) NO_PULL="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "$USERNAME" ]] || { usage; die "--user is required"; }

if [[ -z "$INSTALL_DIR" ]]; then
  if is_darwin; then
    INSTALL_DIR="/Users/${USERNAME}/.base-tooling"
  else
    if have getent && getent passwd "$USERNAME" >/dev/null 2>&1; then
      INSTALL_DIR="$(getent passwd "$USERNAME" | cut -d: -f6)/.base-tooling"
    else
      INSTALL_DIR="$HOME/.base-tooling"
      warn "User '$USERNAME' not found via getent; using INSTALL_DIR=$INSTALL_DIR"
    fi
  fi
fi

msg "Base tooling update (Day-2) starting..."
msg "Detected OS: $(uname -s) ($(uname -m))"
msg "Using user: ${USERNAME}"
msg "Repo dir: ${INSTALL_DIR}"

[[ -d "${INSTALL_DIR}/.git" ]] || die "Repo not found at ${INSTALL_DIR}. Run install first."

update_repo() {
  msg "Updating repo..."

  if [[ "$NO_PULL" == "true" ]]; then
    msg "Skipping git pull (--no-pull)."
    return 0
  fi

  # Allow "dirty" working tree if ONLY flake.lock or result/ changed.
  local dirty
  dirty="$(git -C "$INSTALL_DIR" status --porcelain \
    | awk '{print $2}' \
    | grep -vE '^(flake\.lock|result/|result$)$' || true)"

  if [[ -n "$dirty" ]]; then
    die "Working tree has uncommitted changes in ${INSTALL_DIR} (excluding flake.lock/result). Commit/stash them, or re-run with --no-pull."
  fi

  git -C "$INSTALL_DIR" pull --ff-only
  msg "Current branch $(git -C "$INSTALL_DIR" rev-parse --abbrev-ref HEAD) is up to date."
}

apply_configuration() {
  msg "Applying declarative configuration..."
  export BASE_TOOLING_USER="${USERNAME}"

  if is_darwin; then
    require_sudo
    nix build --impure -o "${INSTALL_DIR}/result" "${INSTALL_DIR}#darwinConfigurations.default.system"
    sudo --preserve-env=BASE_TOOLING_USER "${INSTALL_DIR}/result/sw/bin/darwin-rebuild" switch --impure --flake "${INSTALL_DIR}#default"
  else
    nix run github:nix-community/home-manager -- \
      switch -b backup \
      --impure \
      --flake "${INSTALL_DIR}#${USERNAME}@linux"
  fi
}

ensure_linux_bash_environment() {
  if ! is_linux; then
    return 0
  fi

  local HOME_DIR
  HOME_DIR="$(getent passwd "$USERNAME" | cut -d: -f6)"

  if [ -z "$HOME_DIR" ] || [ ! -d "$HOME_DIR" ]; then
    echo "ERROR: Cannot determine home directory for user $USERNAME" >&2
    exit 1
  fi

  local BASHRC="$HOME_DIR/.bashrc"
  local SNIPPET_DIR="$HOME_DIR/.bashrc.d"
  local SNIPPET="$SNIPPET_DIR/base-tooling.sh"

  mkdir -p "$SNIPPET_DIR"

  cat >"$SNIPPET" <<'EOF'
# ---- base-tooling managed block ----

# Load Nix environment
if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
elif [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
  . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi

# direnv hook (only if installed)
if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook bash)"
fi

# ---- /base-tooling ----
EOF

  chown "$USERNAME":"$USERNAME" "$SNIPPET"

  # ensure bashrc exists
  if [ ! -f "$BASHRC" ]; then
    touch "$BASHRC"
    chown "$USERNAME":"$USERNAME" "$BASHRC"
  fi

  if ! grep -q "base-tooling managed block loader" "$BASHRC" 2>/dev/null; then
    cat >>"$BASHRC" <<'EOF'

# base-tooling managed block loader
[ -r "$HOME/.bashrc.d/base-tooling.sh" ] && . "$HOME/.bashrc.d/base-tooling.sh"
EOF
  fi
}

update_repo
ensure_linux_bash_environment
apply_configuration
msg "Done."
