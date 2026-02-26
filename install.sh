#!/usr/bin/env bash
set -euo pipefail

# base-tooling install (Day-0)

msg() { printf '\n==> %s\n' "$*"; }
warn() { printf '\nWARN: %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }
is_darwin() { [[ "$(uname -s)" == "Darwin" ]]; }

require_sudo() {
  if [[ ${EUID:-0} -ne 0 ]]; then
    msg "Sudo privileges required. You may be prompted for your password."
    sudo -v
  fi
}

source_nix_profile() {
  if [[ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
  if [[ -r "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
    # shellcheck disable=SC1091
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
  fi
  if [[ -r /etc/profile.d/nix.sh ]]; then
    # shellcheck disable=SC1091
    . /etc/profile.d/nix.sh
  fi
}

ensure_nix_available() {
  source_nix_profile
  if have nix; then return; fi
  for p in /nix/var/nix/profiles/default/bin/nix "$HOME/.nix-profile/bin/nix"; do
    if [[ -x "$p" ]]; then
      export PATH="$(dirname "$p"):$PATH"
      return
    fi
  done
  die "Nix not found in PATH. Install Nix first, then re-run."
}

with_nix_profile_add_shim() {
  ensure_nix_available

  local real_nix
  real_nix="$(command -v nix)"
  [[ -n "$real_nix" && -x "$real_nix" ]] || die "Could not locate real nix binary."

  local tmp
  tmp="$(mktemp -d 2>/dev/null || mktemp -d -t base-tooling-nixshim)"

  cat >"$tmp/nix" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

REAL_NIX="__REAL_NIX__"

if [[ "${1:-}" == "profile" && "${2:-}" == "add" ]]; then
  shift 2
  exec "$REAL_NIX" profile install "$@"
fi

exec "$REAL_NIX" "$@"
EOF

  perl -0777 -i -pe "s#__REAL_NIX__#${real_nix}#g" "$tmp/nix" 2>/dev/null || \
    sed -i "s#__REAL_NIX__#${real_nix}#g" "$tmp/nix"

  chmod +x "$tmp/nix"

  PATH="$tmp:$PATH" "$@"

  rm -rf "$tmp" >/dev/null 2>&1 || true
}

ensure_shell_integration_linux() {
  msg "Linux: Ensuring shells load Nix + Home Manager environment (idempotent)."
  ensure_nix_available

  local block
  block=$(cat <<'EOF'
# >>> base-tooling:env >>>
# Nix (daemon) environment
if [ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
elif [ -r "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
  . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi

# Home Manager session variables
if [ -r "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
  . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
fi
# <<< base-tooling:env <<<
EOF
)

  local bashrc="$HOME/.bashrc"; touch "$bashrc"
  if ! grep -q "^# >>> base-tooling:env >>>" "$bashrc" 2>/dev/null; then
    printf '\n%s\n' "$block" >> "$bashrc"
  fi

  local profile="$HOME/.profile"; touch "$profile"
  if ! grep -q "^# >>> base-tooling:env >>>" "$profile" 2>/dev/null; then
    printf '\n%s\n' "$block" >> "$profile"
  fi

  local zprofile="$HOME/.zprofile"; touch "$zprofile"
  if ! grep -q "^# >>> base-tooling:zprofile >>>" "$zprofile" 2>/dev/null; then
    cat >>"$zprofile" <<'EOF'
# >>> base-tooling:zprofile >>>
[ -r "$HOME/.profile" ] && . "$HOME/.profile"
# <<< base-tooling:zprofile <<<
EOF
  fi
}

ensure_repo() {
  local install_dir="$1"

  if [[ -d "$install_dir/.git" ]]; then
    msg "Repo already cloned. Fetching latest..."
    git -C "$install_dir" fetch --prune
    git -C "$install_dir" checkout -q main || true
    git -C "$install_dir" pull --ff-only
  else
    msg "Cloning repo into $install_dir"
    git clone https://github.com/konradrenner/base-tooling "$install_dir"
  fi
}

apply_configuration() {
  local install_dir="$1"
  local username="$2"

  msg "Applying declarative configuration..."
  export BASE_TOOLING_USER="$username"

  ensure_nix_available

  if is_darwin; then
    require_sudo
    nix build --impure "${install_dir}#darwinConfigurations.default.system" -L
    sudo BASE_TOOLING_USER="$username" ./result/sw/bin/darwin-rebuild switch --impure --flake "${install_dir}#default"
  else
    msg "Starting Home Manager activation"
    with_nix_profile_add_shim \
      nix run github:nix-community/home-manager -- \
        switch \
        -b before-hm \
        --impure \
        --flake "${install_dir}#${username}@linux"

    ensure_shell_integration_linux
  fi
}

# -------------------- args --------------------
USERNAME=""
INSTALL_DIR="$HOME/.base-tooling"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USERNAME="${2:-}"; shift 2 ;;
    --dir) INSTALL_DIR="${2:-}"; shift 2 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "$USERNAME" ]] || die "Missing --user <name>"

msg "Base tooling install (Day-0) starting..."
msg "Detected OS: $(uname -s) ($(uname -m))"
msg "Using user: $USERNAME"
msg "Repo dir: $INSTALL_DIR"

ensure_nix_available

if ! have git; then
  if is_darwin; then
    die "git not found. Please install Xcode Command Line Tools (xcode-select --install) and re-run."
  else
    msg "Installing git (apt)"
    sudo apt-get update -y
    sudo apt-get install -y git
  fi
fi

ensure_repo "$INSTALL_DIR"
apply_configuration "$INSTALL_DIR" "$USERNAME"

msg "Done."
if ! is_darwin; then
  msg "Open a NEW terminal (or run: source ~/.profile) so PATH updates take effect."
fi
