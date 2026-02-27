#!/usr/bin/env bash
set -euo pipefail

msg() { printf "\n==> %s\n" "$*"; }
err() { printf "\nERROR: %s\n" "$*" >&2; exit 1; }

USERNAME=""
INSTALL_DIR="${HOME}/.base-tooling"
REPO_URL="https://github.com/konradrenner/base-tooling.git"
NO_PULL="false"
DARWIN_TARGET="default"

usage() {
  cat <<'USAGE'
Usage:
  install.sh --user <name> [--dir <path>] [--no-pull] [--darwin-target <name>]

Notes:
- Linux uses Home Manager standalone via: nix run github:nix-community/home-manager -- switch ...
- macOS uses nix-darwin flake output.
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

require_sudo() {
  ensure_sudo
}

ensure_git() {
  if require_cmd git; then return; fi
  if is_darwin; then
    msg "git missing on macOS. Install Xcode Command Line Tools (xcode-select --install) and re-run."
    exit 1
  fi
  msg "Installing git (apt)..."
  sudo apt-get update -y
  sudo apt-get install -y git
}

ensure_nix() {
  if command -v nix >/dev/null 2>&1; then
    msg "Nix already installed."
    return 0
  fi

  msg "Installing Nix (Determinate Nix Installer) with nixbld GID=350..."

  ensure_sudo

  curl -fsSL https://install.determinate.systems/nix \
    | sudo env \
        NIX_INSTALLER_NIX_BUILD_GROUP_ID=350 \
      sh -s -- install linux \
        --determinate \
        --nix-build-group-id 350 \
        --no-modify-profile \
        --no-confirm
  # Make nix available in THIS shell right now (important for non-interactive install via curl|bash)
  if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
}

ensure_flakes() {
  msg "Enabling nix-command + flakes (idempotent)."
  mkdir -p "${HOME}/.config/nix"
  local conf="${HOME}/.config/nix/nix.conf"
  touch "$conf"
  if ! grep -q '^experimental-features *=.*nix-command' "$conf"; then
    printf "\nexperimental-features = nix-command flakes\n" >> "$conf"
  fi
}

ensure_repo() {
  msg "Ensuring repo is present at: ${INSTALL_DIR}"
  if [[ -d "${INSTALL_DIR}/.git" ]]; then
    if [[ "$NO_PULL" == "true" ]]; then
      msg "Repo already present. --no-pull set, skipping git pull."
    else
      msg "Repo already cloned. Fetching latest..."
      git -C "$INSTALL_DIR" pull --ff-only
    fi
  else
    ensure_git
    git clone "$REPO_URL" "$INSTALL_DIR"
  fi
}

ensure_linux_zsh_default() {
  # You want zsh as default on Linux for your user, but bash must remain.
  # IMPORTANT: chsh must point to a system shell listed in /etc/shells (NOT a nix store path).
  if ! is_linux; then return; fi

  msg "Linux: ensuring zsh is installed and set as login shell for user '${USERNAME}' (bash remains installed)."

  # install zsh from OS packages so it's a valid shell in /etc/shells
  if ! command -v zsh >/dev/null 2>&1; then
    msg "Linux: installing zsh via apt (valid login shell)."
    ensure_sudo
    sudo apt-get update -y
    sudo apt-get install -y zsh
  fi

  # set login shell (bash remains installed; we only switch for this user)
  if [ "${SHELL:-}" != "$(command -v zsh)" ]; then
    msg "Linux: setting zsh as login shell for ${USERNAME}."
    ensure_sudo
    sudo chsh -s "$(command -v zsh)" "${USERNAME}"
  fi
}

ensure_linux_shell_integration() {
  # ensures that future shells have nix + hm env without clobbering user's config
  local nix_hook='/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
  local hm_hook='$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh'

  local block
  block=$(
    cat <<'EOF'
# >>> base-tooling (nix + home-manager) >>>
if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
if [ -e "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
  . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
fi
# <<< base-tooling (nix + home-manager) <<<
EOF
  )

  # Bash: login + interactive
  for f in "$HOME/.profile" "$HOME/.bashrc"; do
    touch "$f"
    if ! grep -q 'base-tooling (nix + home-manager)' "$f"; then
      printf "\n%s\n" "$block" >> "$f"
    fi
  done

  # Zsh: login + interactive
  for f in "$HOME/.zprofile" "$HOME/.zshrc"; do
    touch "$f"
    if ! grep -q 'base-tooling (nix + home-manager)' "$f"; then
      printf "\n%s\n" "$block" >> "$f"
    fi
  done
}

apply_configuration() {
  msg "Applying declarative configuration..."
  export BASE_TOOLING_USER="${USERNAME}"

  if is_darwin; then
    ensure_sudo

    # Build to an explicit output path so "result" doesn't confuse people / collide
    local out="/tmp/base-tooling-darwin-system"
    rm -f "$out" 2>/dev/null || true

    nix build --impure -L -o "$out" "${INSTALL_DIR}#darwinConfigurations.${DARWIN_TARGET}.system"
    sudo env BASE_TOOLING_USER="${USERNAME}" "$out/sw/bin/darwin-rebuild" switch --impure --flake "${INSTALL_DIR}#${DARWIN_TARGET}"

  elif is_linux; then
    # No installing home-manager CLI into a profile; just run it.
    nix run github:nix-community/home-manager -- \
      switch \
      -b backup \
      --impure \
      --flake "${INSTALL_DIR}#${USERNAME}@linux"
  else
    err "Unsupported OS: $(uname -s)"
  fi
}

msg "Base tooling install (Day-0) starting..."
msg "Using user: ${USERNAME}"
msg "Repo dir: ${INSTALL_DIR}"

if is_darwin; then msg "Detected OS: Darwin ($(uname -m))"; fi
if is_linux; then msg "Detected OS: Linux ($(uname -m))"; fi

ensure_nix
ensure_flakes
ensure_repo
ensure_linux_shell_integration
apply_configuration
ensure_linux_zsh_default

msg "Done."
msg "Open a NEW terminal so your login shell/env is refreshed."
