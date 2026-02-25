#!/usr/bin/env bash
set -euo pipefail

# base-tooling install (Day-0)
# - clones/updates the repo into ~/.base-tooling
# - applies nix-darwin (macOS) or home-manager (Linux)
# - ensures bash can see Nix + Home Manager env even if user keeps "default" bash dotfiles

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
Usage: install.sh --user <name> [--no-pull]
USAGE
      exit 0
      ;;
    *) err "Unknown argument: $1";;
  esac
done

[[ -n "$USERNAME" ]] || err "--user is required"

INSTALL_DIR="${HOME}/.base-tooling"
REPO_URL="https://github.com/konradrenner/base-tooling.git"
DARWIN_TARGET="default"

ensure_repo() {
  msg "Ensuring repo is present at: ${INSTALL_DIR}"

  if [[ -d "${INSTALL_DIR}/.git" ]]; then
    msg "Repo already cloned."
    if [[ "$NO_PULL" == "0" ]]; then
      msg "Fetching latest..."
      git -C "$INSTALL_DIR" fetch --all --prune
      # keep local changes; don't clobber
      git -C "$INSTALL_DIR" pull --ff-only || msg "Note: fast-forward pull not possible (local commits/changes?). Continuing."
    else
      msg "Skipping pull (--no-pull)."
    fi
  else
    msg "Cloning repo..."
    git clone "$REPO_URL" "$INSTALL_DIR"
  fi
}

# ---- Shell env bootstrapping (Linux + bash) ---------------------------------
# Goal: even if the user restored ~/.bashrc / ~/.profile, they still get:
# - Nix profiles in PATH
# - Home Manager session vars (hm-session-vars.sh), so HM-installed tools (devenv, java, direnv, ...) are visible
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

# ---- Rancher Desktop --------------------------------------------------------
install_rancher_desktop_macos() {
  msg "macOS: Installing Rancher Desktop via Homebrew cask (if missing)..."
  require_cmd brew
  if brew list --cask rancher >/dev/null 2>&1; then
    msg "Rancher Desktop already installed."
  else
    brew install --cask rancher
  fi
}

install_rancher_desktop_linux() {
  msg "Linux: Installing Rancher Desktop from official repo (if possible)..."
  # Rancher Desktop docs: Linux requires x86_64. (We auto-fallback for arm64.)
  if [[ "$(arch)" != "x86_64" && "$(arch)" != "amd64" ]]; then
    msg "Linux: Detected arch $(arch). Rancher Desktop packages are x86_64-only; skipping."
    msg "Linux: Installing Podman as fallback (rootful; works on arm64)."
    require_sudo
    sudo apt-get update -y
    sudo apt-get install -y podman podman-docker podman-compose uidmap slirp4netns
    return 0
  fi

  if command -v rancher-desktop >/dev/null 2>&1; then
    msg "Rancher Desktop already installed."
    return 0
  fi

  require_sudo
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl gnupg

  # From Rancher Desktop docs (deb): https://docs.rancherdesktop.io/getting-started/installation/
  sudo mkdir -p /usr/share/keyrings
  curl -fsSL https://download.opensuse.org/repositories/isv:/Rancher:/stable/deb/Release.key \
    | gpg --dearmor \
    | sudo dd status=none of=/usr/share/keyrings/isv-rancher-stable-archive-keyring.gpg

  echo "deb [signed-by=/usr/share/keyrings/isv-rancher-stable-archive-keyring.gpg] https://download.opensuse.org/repositories/isv:/Rancher:/stable/deb/ ./" \
    | sudo dd status=none of=/etc/apt/sources.list.d/isv-rancher-stable.list

  sudo apt-get update -y
  sudo apt-get install -y rancher-desktop
}

# ---- Apply declarative config ----------------------------------------------
apply_configuration() {
  msg "Applying declarative configuration..."
  export BASE_TOOLING_USER="${USERNAME}"

  if is_darwin; then
    require_sudo
    # Build system derivation (user context). --impure needed for BASE_TOOLING_USER via getEnv.
    nix build --impure "${INSTALL_DIR}#darwinConfigurations.${DARWIN_TARGET}.system" -L
    # Activate as root
    sudo ./result/sw/bin/darwin-rebuild switch --impure --flake "${INSTALL_DIR}#${DARWIN_TARGET}" -L
  else
    # Linux Home Manager configuration for "<user>@linux"
    # -b backups conflicting dotfiles automatically (avoids "would be clobbered")
    nix run github:nix-community/home-manager -- \
      switch \
      -b before-hm \
      --impure \
      --flake "${INSTALL_DIR}#${USERNAME}@linux"
  fi
}

main() {
  msg "Base tooling install (Day-0) starting..."
  msg "Detected OS: $(uname -s) ($(arch))"
  msg "Using user: ${USERNAME}"
  msg "Repo dir: ${INSTALL_DIR}"

  require_cmd git
  require_cmd nix

  ensure_repo

  if is_darwin; then
    install_rancher_desktop_macos
  elif is_linux; then
    install_rancher_desktop_linux
  fi

  apply_configuration

  ensure_linux_shell_env

  msg "Done."
  if is_linux; then
    msg "Open a NEW terminal (or run: source ~/.bashrc) so PATH updates take effect."
  fi
}

main "$@"
