#!/usr/bin/env bash
set -euo pipefail

# base-tooling install (Day-0)
# - Linux: Home Manager standalone config <user>@linux
# - macOS: nix-darwin + Home Manager config default
# This script is meant to be run via curl | bash.

# -----------------
# UI helpers
# -----------------
msg() { printf "\n==> %s\n" "$*"; }
warn() { printf "warning: %s\n" "$*" >&2; }
err() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

# -----------------
# Detect OS/arch
# -----------------
is_darwin() { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux()  { [[ "$(uname -s)" == "Linux" ]]; }
arch()      { uname -m; }

# -----------------
# Args
# -----------------
USERNAME=""
INSTALL_DIR=""
REPO_URL="https://github.com/konradrenner/base-tooling"
DARWIN_TARGET="default"
NO_PULL="0"

usage() {
  cat <<'USAGE'
Usage:
  install.sh --user <name> [--dir <path>] [--no-pull]

Examples:
  curl -fsSL https://raw.githubusercontent.com/konradrenner/base-tooling/main/install.sh | bash -s -- --user koni
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

# Default install dir: $HOME/.base-tooling (for the *current* user running the script)
if [[ -z "$INSTALL_DIR" ]]; then
  INSTALL_DIR="$HOME/.base-tooling"
fi

# -----------------
# Sudo
# -----------------
require_sudo() {
  if ! command -v sudo >/dev/null 2>&1; then
    err "sudo is required"
  fi
  # Warm sudo
  sudo -v
}

# -----------------
# Nix helpers
# -----------------
source_nix_profile_if_needed() {
  # Make nix available even if the current shell/session did not source it.
  # This is especially important for non-login shells and for fresh installations.
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

enable_nix_command_and_flakes() {
  # Idempotent: enable nix-command + flakes via nix.conf
  # (Many installers already do this; we just ensure it.)
  local nix_conf
  if is_darwin; then
    nix_conf="/etc/nix/nix.conf"
  else
    nix_conf="/etc/nix/nix.conf"
  fi

  if [[ ! -f "$nix_conf" ]]; then
    return 0
  fi

  if ! grep -q "experimental-features" "$nix_conf"; then
    require_sudo
    sudo sh -c "printf '\nexperimental-features = nix-command flakes\n' >> '$nix_conf'"
  else
    # ensure flakes is present
    if ! grep -q "flakes" "$nix_conf"; then
      require_sudo
      sudo sh -c "sed -i.bak 's/^experimental-features *= */experimental-features = nix-command flakes /' '$nix_conf' || true"
    fi
  fi
}

# -----------------
# Git / repo
# -----------------
ensure_git() {
  if command -v git >/dev/null 2>&1; then
    return 0
  fi
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
    msg "Repo already cloned. Fetching latest..."
    if [[ "$NO_PULL" == "1" ]]; then
      msg "--no-pull set; skipping git pull."
      return 0
    fi
    git -C "$INSTALL_DIR" fetch --all --prune
    git -C "$INSTALL_DIR" checkout -q main || true
    git -C "$INSTALL_DIR" pull --ff-only
  else
    git clone "$REPO_URL" "$INSTALL_DIR"
  fi
}

# -----------------
# Linux: Rancher Desktop
# -----------------
linux_install_rancher_desktop_repo() {
  # Official docs currently reference the openSUSE Build Service repo.
  # We follow those instructions, but keep it idempotent.
  # If RD is already installed, do nothing.
  if command -v rancher-desktop >/dev/null 2>&1; then
    msg "Rancher Desktop already installed."
    return 0
  fi

  msg "Linux: Installing Rancher Desktop via official repository..."
  require_sudo

  # Dependencies
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl gnupg

  # Keyring
  sudo install -d -m 0755 /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/rancher-desktop.gpg ]]; then
    curl -fsSL https://download.opensuse.org/repositories/isv:/Rancher:/stable/deb/Release.key \
      | sudo gpg --dearmor -o /etc/apt/keyrings/rancher-desktop.gpg
    sudo chmod a+r /etc/apt/keyrings/rancher-desktop.gpg
  fi

  # Repo entry
  if [[ ! -f /etc/apt/sources.list.d/rancher-desktop.list ]]; then
    echo "deb [signed-by=/etc/apt/keyrings/rancher-desktop.gpg] https://download.opensuse.org/repositories/isv:/Rancher:/stable/deb/ ./" \
      | sudo tee /etc/apt/sources.list.d/rancher-desktop.list >/dev/null
  fi

  sudo apt-get update -y
  sudo apt-get install -y rancher-desktop
}

# -----------------
# Linux: shell integration (bulletproof)
# -----------------
linux_ensure_nix_on_path_for_bash() {
  # Goal:
  # - keep Ubuntu's default bash
  # - still have nix + HM profile binaries (devenv, java, etc.) on PATH
  # - survive users restoring ~/.bashrc / ~/.profile
  #
  # Strategy:
  # 1) System-wide: ensure /etc/bash.bashrc sources nix-daemon.sh (interactive shells)
  # 2) User-level: add a tiny marker block to ~/.bashrc (works even without login shell)

  local nix_daemon_sh="/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
  local nix_sh="/nix/var/nix/profiles/default/etc/profile.d/nix.sh"

  if [[ ! -r "$nix_daemon_sh" && ! -r "$nix_sh" ]]; then
    warn "Could not find Nix profile scripts under /nix/var/nix/profiles/default/etc/profile.d. PATH integration may not work."
    return 0
  fi

  require_sudo

  # 1) /etc/bash.bashrc (interactive shells)
  local sys_marker_begin="# >>> base-tooling nix env >>>"
  local sys_marker_end="# <<< base-tooling nix env <<<"
  if ! sudo grep -qF "$sys_marker_begin" /etc/bash.bashrc 2>/dev/null; then
    sudo tee -a /etc/bash.bashrc >/dev/null <<EOF

$sys_marker_begin
# Make Nix available in interactive bash shells.
if [ -r "$nix_daemon_sh" ]; then
  . "$nix_daemon_sh"
elif [ -r "$nix_sh" ]; then
  . "$nix_sh"
fi
$sys_marker_end
EOF
  fi

  # 2) ~/.bashrc (user)
  local user_bashrc="$HOME/.bashrc"
  local user_marker_begin="# >>> base-tooling nix env (user) >>>"
  local user_marker_end="# <<< base-tooling nix env (user) <<<"

  touch "$user_bashrc"
  if ! grep -qF "$user_marker_begin" "$user_bashrc"; then
    cat >> "$user_bashrc" <<EOF

$user_marker_begin
# Make Nix + Home Manager profile binaries available in interactive shells.
if [ -r "$nix_daemon_sh" ]; then
  . "$nix_daemon_sh"
elif [ -r "$nix_sh" ]; then
  . "$nix_sh"
fi

# Load Home Manager session variables if present (adds HM-managed bins to PATH)
if [ -r "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
  . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
fi

# direnv hook (only if direnv is installed)
if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook bash)"
fi
$user_marker_end
EOF
  fi
}

# -----------------
# Apply configuration
# -----------------
apply_configuration() {
  msg "Applying declarative configuration..."

  export BASE_TOOLING_USER="$USERNAME"

  # Ensure nix is available in this script execution.
  source_nix_profile_if_needed

  if is_darwin; then
    require_sudo

    # Build system configuration (user context). --impure needed for BASE_TOOLING_USER via getEnv.
    nix build --impure "$INSTALL_DIR#darwinConfigurations.${DARWIN_TARGET}.system"

    # Activate as root; pass BASE_TOOLING_USER into sudo environment explicitly.
    sudo env BASE_TOOLING_USER="$USERNAME" ./result/sw/bin/darwin-rebuild switch --impure --flake "$INSTALL_DIR#${DARWIN_TARGET}"
  else
    # Linux Home Manager configuration for "<user>@linux"
    # -b <ext> ensures existing dotfiles are backed up instead of aborting.
    nix run github:nix-community/home-manager -- \
      switch \
      --impure \
      --flake "$INSTALL_DIR#${USERNAME}@linux" \
      -b before-hm

    # Make sure bash always sees nix + HM profile tools.
    linux_ensure_nix_on_path_for_bash

    # Optional: Rancher Desktop
    linux_install_rancher_desktop_repo
  fi
}

main() {
  msg "Base tooling install (Day-0) starting..."

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

  msg "Nix already installed (assumed)."
  msg "Enabling nix-command + flakes (idempotent)."
  enable_nix_command_and_flakes

  apply_configuration

  msg "Done."
  if is_linux; then
    msg "Open a NEW terminal (or run: source ~/.bashrc) so PATH updates take effect."
  fi
}

main "$@"
