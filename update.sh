#!/usr/bin/env bash
set -euo pipefail

# ----------------------------
# base-tooling update (Day-2)
# ----------------------------

SCRIPT_NAME="$(basename "$0")"

USERNAME=""
INSTALL_DIR=""
DARWIN_TARGET="default"
NO_PULL="0"

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
  $SCRIPT_NAME --user <name> [--dir <path>] [--darwin-target <name>] [--no-pull]

Options:
  --user            Username to configure (required)
  --dir             Repo directory (default: ~/.base-tooling)
  --darwin-target   nix-darwin flake target (default: default)
  --no-pull         Do not git pull (useful if you have local changes)
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user) USERNAME="${2:-}"; shift 2 ;;
      --dir)  INSTALL_DIR="${2:-}"; shift 2 ;;
      --darwin-target) DARWIN_TARGET="${2:-}"; shift 2 ;;
      --no-pull) NO_PULL="1"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown argument: $1" ;;
    esac
  done
  [[ -n "$USERNAME" ]] || die "--user is required"
  [[ -n "${INSTALL_DIR}" ]] || INSTALL_DIR="$HOME/.base-tooling"
}

ensure_linux_bash_nix_integration() {
  is_linux || return 0

  local profile="$HOME/.profile"
  local bashrc="$HOME/.bashrc"
  local marker_begin="# >>> base-tooling: nix init >>>"
  local marker_end="# <<< base-tooling: nix init <<<"

  local nix_sh=""
  for cand in \
    "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" \
    "/etc/profile.d/nix.sh" \
    "$HOME/.nix-profile/etc/profile.d/nix.sh"
  do
    if [[ -r "$cand" ]]; then nix_sh="$cand"; break; fi
  done
  if [[ -z "$nix_sh" ]]; then
    warn "Could not find a nix profile script; skipping bash integration."
    return 0
  fi

  local snippet
  snippet="$marker_begin
if [ -r \"$nix_sh\" ]; then
  . \"$nix_sh\"
fi
$marker_end"

  touch "$profile" "$bashrc"
  for f in "$profile" "$bashrc"; do
    if ! grep -Fq "$marker_begin" "$f"; then
      printf "\n%s\n" "$snippet" >>"$f"
    fi
  done
}

install_rancher_desktop_linux() {
  is_linux || return 0
  if have rancher-desktop || dpkg -s rancher-desktop >/dev/null 2>&1 || rpm -q rancher-desktop >/dev/null 2>&1; then
    msg "Rancher Desktop already installed."
    return 0
  fi
  if [[ "$(arch)" != "x86_64" ]]; then
    warn "Rancher Desktop packages are only available for Linux x86_64. Current arch: $(arch). Skipping."
    return 0
  fi

  msg "Linux: Installing Rancher Desktop from upstream GitHub release (.deb/.rpm) if missing..."

  local api="https://api.github.com/repos/rancher-sandbox/rancher-desktop/releases/latest"
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/base-tooling"
  mkdir -p "$cache"

  local url=""
  if have apt-get; then
    url="$(curl -fsSL "$api" | grep -Eo 'https://[^"]+\.deb' | grep -E '(amd64|x86_64)' | head -n1 || true)"
    [[ -n "$url" ]] || die "Could not find a suitable .deb asset for Rancher Desktop (amd64)."
    local deb="$cache/$(basename "$url")"
    curl -fL --retry 3 --retry-delay 1 -o "$deb" "$url"
    require_sudo
    sudo dpkg -i "$deb" || sudo apt-get -y -f install
  elif have rpm; then
    url="$(curl -fsSL "$api" | grep -Eo 'https://[^"]+\.rpm' | grep -E '(x86_64)' | head -n1 || true)"
    [[ -n "$url" ]] || die "Could not find a suitable .rpm asset for Rancher Desktop (x86_64)."
    local rpmf="$cache/$(basename "$url")"
    curl -fL --retry 3 --retry-delay 1 -o "$rpmf" "$url"
    require_sudo
    sudo rpm -Uvh --replacepkgs "$rpmf"
  else
    warn "Neither apt-get nor rpm found; skipping Rancher Desktop install."
  fi
}

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

    nix build --impure -L "${INSTALL_DIR}#darwinConfigurations.${DARWIN_TARGET}.system"
    sudo env BASE_TOOLING_USER="$USERNAME" ./result/sw/bin/darwin-rebuild switch --impure --flake "${INSTALL_DIR}#${DARWIN_TARGET}"
  else
    ensure_linux_bash_nix_integration

    nix run github:nix-community/home-manager -- \
      switch \
      -b before-hm \
      --impure \
      --flake "${INSTALL_DIR}#${USERNAME}@linux"

    ensure_linux_bash_nix_integration
  fi
}

update_repo() {
  msg "Updating repo..."
  [[ -d "$INSTALL_DIR/.git" ]] || die "Repo not found at $INSTALL_DIR. Run install first."

  if [[ "$NO_PULL" == "1" ]]; then
    msg "--no-pull set; skipping git pull."
    return 0
  fi

  # Only block if there are tracked changes staged/unstaged.
  # (Untracked files like a locally-generated flake.lock shouldn't stop updates.)
  if ! git -C "$INSTALL_DIR" diff --quiet || ! git -C "$INSTALL_DIR" diff --cached --quiet; then
    die "Working tree has uncommitted changes in $INSTALL_DIR. Commit/stash them, or re-run with --no-pull."
  fi

  git -C "$INSTALL_DIR" pull --ff-only
}

main() {
  parse_args "$@"

  msg "Base tooling update (Day-2) starting..."
  msg "Detected OS: $(uname -s) ($(arch))"
  msg "Using user: $USERNAME"
  msg "Repo dir: $INSTALL_DIR"

  have nix || die "Nix is not installed."

  update_repo

  if is_linux; then
    install_rancher_desktop_linux
  fi

  apply_configuration

  msg "Done."
}

main "$@"
