#!/usr/bin/env bash
set -euo pipefail

# base-tooling update (Day-2)
# - Pull latest repo changes (unless --no-pull)
# - Re-apply configuration

msg() { printf "\n==> %s\n" "$*"; }
warn() { printf "warning: %s\n" "$*" >&2; }
err() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

is_darwin() { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux()  { [[ "$(uname -s)" == "Linux" ]]; }
arch()      { uname -m; }

USERNAME=""
INSTALL_DIR=""
REPO_URL="https://github.com/konradrenner/base-tooling"
DARWIN_TARGET="default"
NO_PULL="0"

usage() {
  cat <<'USAGE'
Usage:
  update.sh --user <name> [--dir <path>] [--no-pull]

Examples:
  ~/.base-tooling/update.sh --user koni
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USERNAME="${2:-}"; shift 2;;
    --dir) INSTALL_DIR="${2:-}"; shift 2;;
    --no-pull) NO_PULL="1"; shift;;
    -h|--help) usage; exit 0;;
    *) err "Unknown argument: $1";;
  esac
done

[[ -n "$USERNAME" ]] || { usage; err "--user is required"; }
if [[ -z "$INSTALL_DIR" ]]; then
  INSTALL_DIR="$HOME/.base-tooling"
fi

require_sudo() {
  command -v sudo >/dev/null 2>&1 || err "sudo is required"
  sudo -v
}

source_nix_profile_if_needed() {
  if command -v nix >/dev/null 2>&1; then
    return 0
  fi
  local candidates=(
    "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
    "/nix/var/nix/profiles/default/etc/profile.d/nix.sh"
    "$HOME/.nix-profile/etc/profile.d/nix.sh"
  )
  for f in "${candidates[@]}"; do
    if [[ -r "$f" ]]; then
      # shellcheck disable=SC1090
      . "$f"
      break
    fi
  done
}

ensure_git() {
  command -v git >/dev/null 2>&1 && return 0
  if is_darwin; then
    err "git is required on macOS. Install Xcode CLT: xcode-select --install"
  fi
  msg "Installing git..."
  require_sudo
  sudo apt-get update -y
  sudo apt-get install -y git
}

ensure_repo() {
  msg "Ensuring repo is present at: $INSTALL_DIR"
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    if [[ "$NO_PULL" == "1" ]]; then
      msg "--no-pull set; skipping git pull."
      return 0
    fi

    # If the user has local modifications, refuse by default.
    if ! git -C "$INSTALL_DIR" diff --quiet || ! git -C "$INSTALL_DIR" diff --cached --quiet; then
      err "Working tree has uncommitted changes in $INSTALL_DIR. Commit/stash them, or re-run with --no-pull."
    fi

    msg "Updating repo..."
    git -C "$INSTALL_DIR" fetch --all --prune
    git -C "$INSTALL_DIR" checkout -q main || true
    git -C "$INSTALL_DIR" pull --ff-only
  else
    git clone "$REPO_URL" "$INSTALL_DIR"
  fi
}

linux_install_rancher_desktop_repo() {
  if command -v rancher-desktop >/dev/null 2>&1; then
    msg "Rancher Desktop already installed."
    return 0
  fi

  msg "Linux: Installing Rancher Desktop via official repository..."
  require_sudo

  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl gnupg

  sudo install -d -m 0755 /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/rancher-desktop.gpg ]]; then
    curl -fsSL https://download.opensuse.org/repositories/isv:/Rancher:/stable/deb/Release.key \
      | sudo gpg --dearmor -o /etc/apt/keyrings/rancher-desktop.gpg
    sudo chmod a+r /etc/apt/keyrings/rancher-desktop.gpg
  fi

  if [[ ! -f /etc/apt/sources.list.d/rancher-desktop.list ]]; then
    echo "deb [signed-by=/etc/apt/keyrings/rancher-desktop.gpg] https://download.opensuse.org/repositories/isv:/Rancher:/stable/deb/ ./" \
      | sudo tee /etc/apt/sources.list.d/rancher-desktop.list >/dev/null
  fi

  sudo apt-get update -y
  sudo apt-get install -y rancher-desktop
}

linux_ensure_nix_on_path_for_bash() {
  local nix_daemon_sh="/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
  local nix_sh="/nix/var/nix/profiles/default/etc/profile.d/nix.sh"

  if [[ ! -r "$nix_daemon_sh" && ! -r "$nix_sh" ]]; then
    warn "Could not find Nix profile scripts under /nix/var/nix/profiles/default/etc/profile.d. PATH integration may not work."
    return 0
  fi

  require_sudo

  local sys_marker_begin="# >>> base-tooling nix env >>>"
  local sys_marker_end="# <<< base-tooling nix env <<<"
  if ! sudo grep -qF "$sys_marker_begin" /etc/bash.bashrc 2>/dev/null; then
    sudo tee -a /etc/bash.bashrc >/dev/null <<EOF

$sys_marker_begin
if [ -r "$nix_daemon_sh" ]; then
  . "$nix_daemon_sh"
elif [ -r "$nix_sh" ]; then
  . "$nix_sh"
fi
$sys_marker_end
EOF
  fi

  local user_bashrc="$HOME/.bashrc"
  local user_marker_begin="# >>> base-tooling nix env (user) >>>"
  local user_marker_end="# <<< base-tooling nix env (user) <<<"

  touch "$user_bashrc"
  if ! grep -qF "$user_marker_begin" "$user_bashrc"; then
    cat >> "$user_bashrc" <<EOF

$user_marker_begin
if [ -r "$nix_daemon_sh" ]; then
  . "$nix_daemon_sh"
elif [ -r "$nix_sh" ]; then
  . "$nix_sh"
fi

if [ -r "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
  . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
fi

if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook bash)"
fi
$user_marker_end
EOF
  fi
}

apply_configuration() {
  msg "Applying declarative configuration..."
  export BASE_TOOLING_USER="$USERNAME"

  source_nix_profile_if_needed

  if is_darwin; then
    require_sudo
    nix build --impure "$INSTALL_DIR#darwinConfigurations.${DARWIN_TARGET}.system"
    sudo env BASE_TOOLING_USER="$USERNAME" ./result/sw/bin/darwin-rebuild switch --impure --flake "$INSTALL_DIR#${DARWIN_TARGET}"
  else
    nix run github:nix-community/home-manager -- \
      switch \
      --impure \
      --flake "$INSTALL_DIR#${USERNAME}@linux" \
      -b before-hm

    linux_ensure_nix_on_path_for_bash
    linux_install_rancher_desktop_repo
  fi
}

main() {
  msg "Base tooling update (Day-2) starting..."

  if is_darwin; then
    msg "Detected OS: Darwin ($(arch))"
  elif is_linux; then
    msg "Detected OS: Linux ($(arch))"
  else
    err "Unsupported OS: $(uname -s)"
  fi

  msg "Using user: $USERNAME"
  msg "Repo dir: $INSTALL_DIR"

  ensure_git
  ensure_repo

  apply_configuration

  msg "Done."
  if is_linux; then
    msg "Open a NEW terminal (or run: source ~/.bashrc) so PATH updates take effect."
  fi
}

main "$@"
