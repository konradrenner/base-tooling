#!/usr/bin/env bash
set -euo pipefail

# base-tooling update (Day-2)
# Usage:
#   ~/.base-tooling/update.sh --user <name> [--no-pull]

msg() { printf '\n==> %s\n' "$*"; }
warn() { printf '\nWARN: %s\n' "$*" >&2; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

require_sudo() {
  if have sudo; then
    msg "Sudo privileges required. You may be prompted for your password."
    sudo -v
  else
    die "sudo is required but not found."
  fi
}

is_darwin() { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux() { [[ "$(uname -s)" == "Linux" ]]; }

arch() {
  local a
  a="$(uname -m)"
  case "$a" in
    x86_64|amd64) echo "x86_64";;
    aarch64|arm64) echo "aarch64";;
    *) echo "$a";;
  esac
}

user_home() {
  local u="$1"
  if is_darwin; then
    dscl . -read "/Users/$u" NFSHomeDirectory 2>/dev/null | awk '{print $2}' || true
  else
    getent passwd "$u" 2>/dev/null | cut -d: -f6 || true
  fi
}

source_nix_profile_if_needed() {
  if have nix; then return 0; fi
  if [[ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  elif [[ -e /nix/var/nix/profiles/default/etc/profile.d/nix.sh ]]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix.sh
  fi
  if [[ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
    # shellcheck disable=SC1091
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
  fi
}

USERNAME=""
NO_PULL=0
DARWIN_TARGET="default"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USERNAME="${2:-}"; shift 2;;
    --no-pull) NO_PULL=1; shift;;
    --darwin-target) DARWIN_TARGET="${2:-default}"; shift 2;;
    -h|--help)
      cat <<EOF
Usage: update.sh --user <name> [--no-pull] [--darwin-target default]
EOF
      exit 0
      ;;
    *) die "Unknown argument: $1";;
  esac
done

[[ -n "$USERNAME" ]] || die "Missing --user <name>"

OS="$(uname -s)"
ARCH="$(arch)"

msg "Base tooling update (Day-2) starting..."
msg "Detected OS: ${OS} (${ARCH})"
msg "Using user: ${USERNAME}"

HOME_DIR="$(user_home "$USERNAME")"
[[ -n "$HOME_DIR" ]] || die "Could not determine home directory for user '$USERNAME'"

INSTALL_DIR="${HOME_DIR}/.base-tooling"
msg "Repo dir: ${INSTALL_DIR}"

[[ -d "$INSTALL_DIR/.git" ]] || die "Repo not found at ${INSTALL_DIR}. Run install.sh first."

msg "Updating repo..."
if [[ "$NO_PULL" -eq 0 ]]; then
  if [[ -n "$(git -C "$INSTALL_DIR" status --porcelain)" ]]; then
    die "Working tree has uncommitted changes in ${INSTALL_DIR}. Commit/stash them, or re-run with --no-pull."
  fi
  git -C "$INSTALL_DIR" pull --ff-only
else
  msg "--no-pull set; skipping git pull."
fi

msg "Applying declarative configuration..."
export BASE_TOOLING_USER="$USERNAME"

source_nix_profile_if_needed
have nix || die "nix is not in PATH for this shell. Open a new terminal or ensure nix-daemon profile is sourced."

if is_darwin; then
  require_sudo
  nix build --impure "${INSTALL_DIR}#darwinConfigurations.${DARWIN_TARGET}.system" -L
  sudo "${INSTALL_DIR}/result/sw/bin/darwin-rebuild" switch --impure --flake "${INSTALL_DIR}#${DARWIN_TARGET}"
else
  nix run github:nix-community/home-manager -- \
    switch \
    --impure \
    --flake "${INSTALL_DIR}#${USERNAME}@linux"

  # Ensure `home-manager` command is always available.
  local_bin="${HOME_DIR}/.local/bin"
  mkdir -p "$local_bin"
  cat > "$local_bin/home-manager" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if ! command -v nix >/dev/null 2>&1; then
  if [[ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  elif [[ -e /nix/var/nix/profiles/default/etc/profile.d/nix.sh ]]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix.sh
  elif [[ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
    # shellcheck disable=SC1091
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
  fi
fi
exec nix run github:nix-community/home-manager -- "$@"
EOF
  chmod +x "$local_bin/home-manager"

  prof="${HOME_DIR}/.profile"
  touch "$prof"
  if ! grep -q 'base-tooling:localbin' "$prof"; then
    cat >> "$prof" <<'EOF'

# base-tooling:localbin (ensure ~/.local/bin on PATH)
if [ -d "$HOME/.local/bin" ]; then
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH="$HOME/.local/bin:$PATH" ;;
  esac
fi
EOF
  fi

  msg "Linux: ensured 'home-manager' command via ~/.local/bin/home-manager"
fi

msg "Done."
