#!/usr/bin/env bash
set -euo pipefail

# base-tooling install (Day-0)
# - Clones/updates repo to ~/.base-tooling
# - Applies configuration:
#   * macOS: nix-darwin + home-manager module
#   * Linux: home-manager standalone
# - Ensures bash on Linux picks up Nix + Home Manager env (without changing your prompt/theme)

SCRIPT_NAME="$(basename "$0")"
REPO_URL_DEFAULT="https://github.com/konradrenner/base-tooling.git"
INSTALL_DIR_DEFAULT="$HOME/.base-tooling"
DARWIN_TARGET_DEFAULT="default"

msg() { printf "\n==> %s\n" "$*"; }
warn() { printf "warning: %s\n" "$*" >&2; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

is_darwin() { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux()  { [[ "$(uname -s)" == "Linux"  ]]; }

arch() {
  local m; m="$(uname -m)"
  case "$m" in
    x86_64|amd64) echo "x86_64" ;;
    aarch64|arm64) echo "aarch64" ;;
    *) echo "$m" ;;
  esac
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

require_sudo() {
  msg "Sudo privileges required. You may be prompted for your password."
  sudo -v
}

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME --user <username> [--repo <git-url>] [--dir <path>] [--darwin-target <name>]

Examples:
  curl -fsSL https://raw.githubusercontent.com/konradrenner/base-tooling/main/install.sh | bash -s -- --user koni
EOF
}

USERNAME=""
REPO_URL="$REPO_URL_DEFAULT"
INSTALL_DIR="$INSTALL_DIR_DEFAULT"
DARWIN_TARGET="$DARWIN_TARGET_DEFAULT"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USERNAME="${2:-}"; shift 2;;
    --repo) REPO_URL="${2:-}"; shift 2;;
    --dir) INSTALL_DIR="${2:-}"; shift 2;;
    --darwin-target) DARWIN_TARGET="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "Unknown argument: $1";;
  esac
done

[[ -n "$USERNAME" ]] || { usage; die "--user is required"; }

msg "Base tooling install (Day-0) starting..."
msg "Detected OS: $(uname -s) ($(arch))"
msg "Using user: $USERNAME"
msg "Repo dir: $INSTALL_DIR"

need_cmd git
need_cmd curl

# Nix detection (we don't install Nix here; assume it's already installed as per your environment)
if command -v nix >/dev/null 2>&1; then
  msg "Nix already installed."
else
  die "Nix is not installed. Install Nix first, then rerun."
fi

enable_nix_features() {
  msg "Enabling nix-command + flakes (idempotent)."
  mkdir -p "$HOME/.config/nix"
  local conf="$HOME/.config/nix/nix.conf"
  touch "$conf"
  if ! grep -qE '^\s*experimental-features\s*=' "$conf"; then
    printf "\nexperimental-features = nix-command flakes\n" >> "$conf"
  else
    # Ensure both flags present
    if ! grep -q "nix-command" "$conf" || ! grep -q "flakes" "$conf"; then
      # replace the line with union
      local line
      line="$(grep -E '^\s*experimental-features\s*=' "$conf" | tail -n1)"
      # shell-safe: just append if missing
      if ! grep -q "nix-command" "$conf"; then printf "\nexperimental-features = nix-command flakes\n" >> "$conf"; fi
    fi
  fi
}

ensure_repo() {
  msg "Ensuring repo is present at: $INSTALL_DIR"
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    msg "Repo already cloned. Fetching latest..."
    git -C "$INSTALL_DIR" fetch --all --prune
    # Keep local changes (e.g., flake.lock) and just fast-forward if possible
    git -C "$INSTALL_DIR" merge --ff-only origin/main >/dev/null 2>&1 || true
  else
    msg "Cloning repo..."
    git clone "$REPO_URL" "$INSTALL_DIR"
  fi
}

ensure_bash_sees_nix_linux() {
  # Keep Ubuntu's default bash style; only ensure Nix/HM env is loaded for interactive shells.
  msg "Linux: Ensuring bash sees Nix + Home Manager environment (idempotent)."

  local bashrc="$HOME/.bashrc"
  touch "$bashrc"

  local begin="# >>> base-tooling: nix+home-manager >>>"
  local end="# <<< base-tooling: nix+home-manager <<<"

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

    # Build system configuration (user context). --impure needed for BASE_TOOLING_USER via getEnv.
    nix build --impure "${INSTALL_DIR}#darwinConfigurations.${DARWIN_TARGET}.system"

    # Activate as root (preserve BASE_TOOLING_USER)
    sudo env BASE_TOOLING_USER="$USERNAME" ./result/sw/bin/darwin-rebuild switch --impure --flake "${INSTALL_DIR}#${DARWIN_TARGET}"
  elif is_linux; then
    # Linux Home Manager configuration for "<user>@linux"
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

enable_nix_features
ensure_repo
apply_configuration

msg "Done."
