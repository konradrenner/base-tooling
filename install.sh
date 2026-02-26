#!/usr/bin/env bash
set -euo pipefail

# base-tooling install (Day-0)
# - clones/updates the repo into ~/.base-tooling (or $BASE_TOOLING_DIR)
# - applies declarative config via nix-darwin (macOS) or Home Manager (Linux)
# - keeps bash installed; on Linux we switch *your user* to zsh (system /usr/bin/zsh)

msg() { printf "\n==> %s\n" "$*"; }
warn() { printf "\nWARN: %s\n" "$*" >&2; }
die() { printf "\nERROR: %s\n" "$*" >&2; exit 1; }

is_darwin() { [ "$(uname -s)" = "Darwin" ]; }
is_linux()  { [ "$(uname -s)" = "Linux" ]; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

require_sudo() {
  if sudo -n true 2>/dev/null; then
    return
  fi
  msg "Sudo privileges required. You may be prompted for your password."
  sudo true
}

usage() {
  cat <<'EOF'
Usage: install.sh --user <name> [--dir <path>]

Options:
  --user <name>   Username used inside the flake (BASE_TOOLING_USER)
  --dir  <path>   Install directory (default: ~/.base-tooling)
EOF
}

USERNAME=""
INSTALL_DIR="${BASE_TOOLING_DIR:-$HOME/.base-tooling}"

while [ "${1:-}" != "" ]; do
  case "$1" in
    --user) USERNAME="${2:-}"; shift 2;;
    --dir)  INSTALL_DIR="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "Unknown argument: $1";;
  esac
done

[ -n "$USERNAME" ] || { usage; die "--user is required"; }

detect_arch() { uname -m; }
detect_os() {
  if is_darwin; then echo "Darwin"; else echo "Linux"; fi
}

ensure_nix() {
  if command -v nix >/dev/null 2>&1; then
    msg "Nix already installed."
    return
  fi
  die "Nix is not installed. Install Nix first, then re-run this script."
}

enable_flakes() {
  msg "Enabling nix-command + flakes (idempotent)."
  # Best-effort; different installs manage this differently.
  mkdir -p "$HOME/.config/nix"
  local conf="$HOME/.config/nix/nix.conf"
  touch "$conf"
  if ! grep -q '^experimental-features *=.*nix-command' "$conf" 2>/dev/null; then
    printf "\nexperimental-features = nix-command flakes\n" >> "$conf"
  fi
}

ensure_git() {
  if command -v git >/dev/null 2>&1; then
    msg "git already installed."
    return
  fi
  if is_darwin; then
    die "git missing. Install Xcode Command Line Tools first (xcode-select --install)."
  fi
  msg "Installing git (apt)..."
  require_sudo
  sudo apt-get update -y
  sudo apt-get install -y git
}

ensure_repo() {
  msg "Ensuring repo is present at: $INSTALL_DIR"
  if [ -d "$INSTALL_DIR/.git" ]; then
    msg "Repo already cloned. Fetching latest..."
    git -C "$INSTALL_DIR" fetch --prune origin
    git -C "$INSTALL_DIR" reset --hard origin/main
  else
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone https://github.com/konradrenner/base-tooling "$INSTALL_DIR"
  fi
}

# Nix 2.29 removed `nix profile add` (renamed to `nix profile install`).
# Some Home Manager code paths still call `nix profile add`, so we install a tiny wrapper
# earlier in PATH that translates "profile add" -> "profile install".
ensure_nix_profile_add_wrapper() {
  if ! is_linux; then
    return
  fi

  # If it already works, do nothing.
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

  # Make sure /usr/bin/zsh is allowed
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
    # -b backs up existing dotfiles automatically (prevents 'would be clobbered').
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
  msg "Base tooling install (Day-0) starting..."
  msg "Detected OS: $(detect_os) ($(detect_arch))"
  msg "Using user: $USERNAME"
  msg "Repo dir: $INSTALL_DIR"

  ensure_nix
  enable_flakes
  ensure_git
  ensure_repo
  apply_configuration

  msg "Done."
  if is_linux; then
    msg "Open a NEW terminal so your login shell change (zsh) takes effect."
  fi
}

main "$@"
