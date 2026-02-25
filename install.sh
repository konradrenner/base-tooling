#!/usr/bin/env bash
set -euo pipefail

# ----------------------------
# base-tooling install (Day-0)
# ----------------------------

SCRIPT_NAME="$(basename "$0")"
REPO_URL_DEFAULT="https://github.com/konradrenner/base-tooling.git"

# Defaults
USERNAME=""
INSTALL_DIR=""
DARWIN_TARGET="default"
REPO_URL="$REPO_URL_DEFAULT"
NO_PULL="0"

# ---------- helpers ----------
msg() { echo -e "\n==> $*"; }
warn() { echo "WARNING: $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

is_darwin() { [[ "$(uname -s)" == "Darwin" ]]; }
is_linux()  { [[ "$(uname -s)" == "Linux" ]]; }

arch() { uname -m; }

require_sudo() {
  if ! have sudo; then die "sudo is required."; fi
  msg "Sudo privileges required. You may be prompted for your password."
  sudo -v
}

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME --user <name> [--repo <git-url>] [--dir <path>] [--darwin-target <name>] [--no-pull]

Options:
  --user            Username to configure (required). Exported as BASE_TOOLING_USER for nix eval/build.
  --repo            Git repo URL (default: $REPO_URL_DEFAULT)
  --dir             Install directory (default: ~/.base-tooling or ~/.base-tooling on macOS; ~/.base-tooling on Linux)
  --darwin-target   nix-darwin flake target (default: default)
  --no-pull         Do not git pull if repo already exists
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user) USERNAME="${2:-}"; shift 2 ;;
      --repo) REPO_URL="${2:-}"; shift 2 ;;
      --dir)  INSTALL_DIR="${2:-}"; shift 2 ;;
      --darwin-target) DARWIN_TARGET="${2:-}"; shift 2 ;;
      --no-pull) NO_PULL="1"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown argument: $1" ;;
    esac
  done

  [[ -n "$USERNAME" ]] || die "--user is required"
  if [[ -z "$INSTALL_DIR" ]]; then
    if is_darwin; then
      INSTALL_DIR="/Users/$USER/.base-tooling"
    else
      INSTALL_DIR="$HOME/.base-tooling"
    fi
  fi
}

ensure_nix_flakes() {
  msg "Enabling nix-command + flakes (idempotent)."
  # Try both nix.conf locations depending on single-/multi-user installs.
  local conf_paths=(
    "/etc/nix/nix.conf"
    "$HOME/.config/nix/nix.conf"
  )
  local conf=""
  for p in "${conf_paths[@]}"; do
    if [[ -e "$p" ]]; then conf="$p"; break; fi
  done
  if [[ -z "$conf" ]]; then
    # Prefer user config if possible.
    mkdir -p "$HOME/.config/nix"
    conf="$HOME/.config/nix/nix.conf"
    touch "$conf"
  fi

  if ! grep -qE '^\s*experimental-features\s*=' "$conf"; then
    echo 'experimental-features = nix-command flakes' >>"$conf"
  elif ! grep -qE 'nix-command' "$conf" || ! grep -qE 'flakes' "$conf"; then
    # Replace line to include both
    sed -i.bak -E 's/^\s*experimental-features\s*=.*/experimental-features = nix-command flakes/' "$conf" || true
  fi
}

ensure_repo() {
  msg "Ensuring repo is present at: $INSTALL_DIR"
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    msg "Repo already cloned."
    if [[ "$NO_PULL" == "0" ]]; then
      msg "Fetching latest..."
      git -C "$INSTALL_DIR" pull --ff-only
    else
      msg "--no-pull set; skipping git pull."
    fi
  else
    msg "Cloning..."
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone "$REPO_URL" "$INSTALL_DIR"
  fi
}

# Ensure the user's interactive bash sessions can see Nix-installed tools
# even if ~/.bashrc and ~/.profile were restored/changed manually.
ensure_linux_bash_nix_integration() {
  [[ "$(uname -s)" == "Linux" ]] || return 0

  local profile="$HOME/.profile"
  local bashrc="$HOME/.bashrc"
  local marker_begin="# >>> base-tooling: nix init >>>"
  local marker_end="# <<< base-tooling: nix init <<<"

  # Find a nix profile script that exists (multi-user vs single-user installs).
  local nix_sh=""
  for cand in \
    "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" \
    "/etc/profile.d/nix.sh" \
    "$HOME/.nix-profile/etc/profile.d/nix.sh"
  do
    if [[ -r "$cand" ]]; then nix_sh="$cand"; break; fi
  done

  if [[ -z "$nix_sh" ]]; then
    warn "Could not find a nix profile script (nix-daemon.sh / nix.sh). Skipping bash integration."
    return 0
  fi

  local snippet
  snippet="$marker_begin
# Ensure Nix environment is available in bash (PATH, MANPATH, etc.)
if [ -r \"$nix_sh\" ]; then
  . \"$nix_sh\"
fi
$marker_end"

  mkdir -p "$(dirname "$profile")"
  touch "$profile"
  touch "$bashrc"

  # Idempotently ensure snippet exists in both files.
  for f in "$profile" "$bashrc"; do
    if ! grep -Fq "$marker_begin" "$f"; then
      printf "\n%s\n" "$snippet" >>"$f"
    fi
  done
}

# Rancher Desktop: only supported on Linux x86_64 per upstream docs.
install_rancher_desktop_linux() {
  is_linux || return 0

  if have rancher-desktop || dpkg -s rancher-desktop >/dev/null 2>&1 || rpm -q rancher-desktop >/dev/null 2>&1; then
    msg "Rancher Desktop already installed."
    return 0
  fi

  if [[ "$(arch)" != "x86_64" ]]; then
    warn "Rancher Desktop upstream packages are only available for Linux x86_64. Current arch: $(arch). Skipping."
    return 0
  fi

  msg "Linux: Installing Rancher Desktop from upstream GitHub release (.deb/.rpm) if missing..."

  local api="https://api.github.com/repos/rancher-sandbox/rancher-desktop/releases/latest"
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/base-tooling"
  mkdir -p "$cache"

  local url=""
  if have apt-get; then
    url="$(curl -fsSL "$api" | grep -Eo 'https://[^"]+\.deb' | grep -E '(amd64|x86_64)' | head -n1 || true)"
    [[ -n "$url" ]] || die "Could not find a suitable .deb asset for Rancher Desktop (amd64) from $api"
    local deb="$cache/$(basename "$url")"
    curl -fL --retry 3 --retry-delay 1 -o "$deb" "$url"
    require_sudo
    sudo dpkg -i "$deb" || sudo apt-get -y -f install
  elif have rpm; then
    url="$(curl -fsSL "$api" | grep -Eo 'https://[^"]+\.rpm' | grep -E '(x86_64)' | head -n1 || true)"
    [[ -n "$url" ]] || die "Could not find a suitable .rpm asset for Rancher Desktop (x86_64) from $api"
    local rpmf="$cache/$(basename "$url")"
    curl -fL --retry 3 --retry-delay 1 -o "$rpmf" "$url"
    require_sudo
    sudo rpm -Uvh --replacepkgs "$rpmf"
  else
    warn "Neither apt-get nor rpm found; skipping Rancher Desktop install."
  fi
}

# nix-darwin can abort if /etc/nix/nix.conf exists with unexpected content.
# We follow nix-darwin's recommendation and rename it automatically once.
fix_darwin_etc_nix_conf_conflict() {
  is_darwin || return 0
  if [[ -f /etc/nix/nix.conf ]] && [[ ! -f /etc/nix/nix.conf.before-nix-darwin ]]; then
    msg "macOS: Detected /etc/nix/nix.conf which may block nix-darwin activation. Renaming to nix.conf.before-nix-darwin"
    require_sudo
    sudo mv /etc/nix/nix.conf /etc/nix/nix.conf.before-nix-darwin
  fi
}

apply_configuration() {
  msg "Applying declarative configuration..."
  export BASE_TOOLING_USER="$USERNAME"

  if is_darwin; then
    require_sudo
    fix_darwin_etc_nix_conf_conflict

    # Build system configuration (user context). --impure needed for BASE_TOOLING_USER via getEnv.
    nix build --impure -L "${INSTALL_DIR}#darwinConfigurations.${DARWIN_TARGET}.system"

    # Activate as root (preserve BASE_TOOLING_USER)
    sudo env BASE_TOOLING_USER="$USERNAME" ./result/sw/bin/darwin-rebuild switch --impure --flake "${INSTALL_DIR}#${DARWIN_TARGET}"
  else
    ensure_linux_bash_nix_integration

    # Linux Home Manager configuration for "<user>@linux"
    nix run github:nix-community/home-manager -- \
      switch \
      -b before-hm \
      --impure \
      --flake "${INSTALL_DIR}#${USERNAME}@linux"

    ensure_linux_bash_nix_integration
  fi
}

main() {
  parse_args "$@"

  msg "Base tooling install (Day-0) starting..."
  msg "Detected OS: $(uname -s) ($(arch))"
  msg "Using user: $USERNAME"
  msg "Repo dir: $INSTALL_DIR"

  if ! have nix; then
    die "Nix is not installed. Install Nix first, then re-run."
  else
    msg "Nix already installed."
  fi

  ensure_nix_flakes

  if is_darwin; then
    if ! have brew; then
      warn "Homebrew not found. Some macOS tooling may rely on it."
    else
      msg "Homebrew already installed."
    fi
  fi

  if ! have git; then
    die "git is required."
  else
    msg "git already installed."
  fi

  ensure_repo

  # Optional extras
  if is_linux; then
    install_rancher_desktop_linux
  fi

  apply_configuration

  msg "Done."
}

main "$@"
