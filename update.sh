#!/usr/bin/env bash
set -euo pipefail

# base-tooling update (Day-2)

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

# Load Nix into PATH for non-login shells.
source_nix_profile() {
  # Multi-user daemon install
  if [[ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
  # Single-user
  if [[ -r "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
    # shellcheck disable=SC1091
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
  fi
  # Some distros
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

# Nix 2.29 dropped `nix profile add`. Home Manager (depending on version)
# may still call it. This shim translates `nix profile add` -> `nix profile install`.
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

  # inject real nix path
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

# Home Manager session variables (standalone HM creates this in the user profile)
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
# Load the same environment for zsh login shells
[ -r "$HOME/.profile" ] && . "$HOME/.profile"
# <<< base-tooling:zprofile <<<
EOF
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

    # Run HM with the nix shim in PATH so `nix profile add` keeps working.
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
NO_PULL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USERNAME="${2:-}"; shift 2 ;;
    --dir) INSTALL_DIR="${2:-}"; shift 2 ;;
    --no-pull) NO_PULL=1; shift ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "$USERNAME" ]] || die "Missing --user <name>"

msg "Base tooling update (Day-2) starting..."
msg "Detected OS: $(uname -s) ($(uname -m))"
msg "Using user: $USERNAME"
msg "Repo dir: $INSTALL_DIR"

ensure_nix_available

if [[ ! -d "$INSTALL_DIR/.git" ]]; then
  die "Repo not found at $INSTALL_DIR. Run install.sh first."
fi

if [[ $NO_PULL -eq 0 ]]; then
  msg "Updating repo..."
  git -C "$INSTALL_DIR" fetch --prune
  git -C "$INSTALL_DIR" checkout -q main || true
  git -C "$INSTALL_DIR" pull --ff-only
else
  msg "Skipping git pull (--no-pull)."
fi

apply_configuration "$INSTALL_DIR" "$USERNAME"

msg "Done."
if ! is_darwin; then
  msg "Open a NEW terminal (or run: source ~/.profile) so PATH updates take effect."
fi
