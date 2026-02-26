#!/usr/bin/env bash
set -euo pipefail
trap 'echo "ERROR: update.sh failed at line $LINENO." >&2' ERR

INSTALL_DIR="${HOME}/.base-tooling"
DARWIN_TARGET="default"

is_linux()  { [ "$(uname -s)" = "Linux" ]; }
is_darwin() { [ "$(uname -s)" = "Darwin" ]; }

msg() { printf "\n==> %s\n" "$*"; }

require_cmd() {
  local c="$1"
  if ! command -v "$c" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $c" >&2
    exit 1
  fi
}

require_sudo() {
  require_cmd sudo
  if ! sudo -n true 2>/dev/null; then
    echo "Sudo privileges required. You may be prompted for your password."
    sudo true
  fi
}

# --- Nix compatibility shim -----------------------------------------------
# Some older tools (incl. some Home Manager builds) still invoke:
#   nix profile add ...
# Newer Nix versions may have removed/never supported "profile add" and use:
#   nix profile install ...
# We create a temporary "nix" wrapper early in PATH for the duration of the
# Home Manager run to translate "profile add" -> "profile install".
nix_needs_profile_add_shim() {
  local out
  out="$(nix profile add --help 2>&1 || true)"
  echo "$out" | grep -qi "not a recognised command"
}

with_nix_profile_add_shim() {
  # Usage: with_nix_profile_add_shim <command> [args...]
  if ! command -v nix >/dev/null 2>&1; then
    "$@"
    return
  fi

  if ! nix_needs_profile_add_shim; then
    "$@"
    return
  fi

  msg "Linux: Enabling Nix 'profile add' compatibility shim for this run."
  (
    set -euo pipefail
    local real_nix tmpdir
    real_nix="$(command -v nix)"
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    cat >"$tmpdir/nix" <<EOF
#!/usr/bin/env bash
set -euo pipefail
REAL_NIX="$real_nix"
if [[ "\${1:-}" == "profile" && "\${2:-}" == "add" ]]; then
  shift 2
  exec "\$REAL_NIX" profile install "\$@"
fi
exec "\$REAL_NIX" "\$@"
EOF
    chmod +x "$tmpdir/nix"
    export PATH="$tmpdir:$PATH"
    "$@"
  )
}


usage() {
  cat <<'USAGE'
Usage:
  update.sh --user <username> [--update-rancher] [--no-pull] [--dir <path>]

Required:
  --user <username>     Local account name (e.g. koni)

Optional:
  --update-rancher      (Linux) Update Rancher Desktop to latest release (.deb/.rpm)
  --no-pull             Do not run git pull (useful if you are on a local branch)
  --dir <path>          Repo directory (default: ~/.base-tooling)

Examples:
  ~/.base-tooling/update.sh --user koni
  ~/.base-tooling/update.sh --user koni --update-rancher
USAGE
}

USERNAME=""
UPDATE_RANCHER=0
NO_PULL=0

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --user)
        shift
        USERNAME="${1:-}"
        shift
        ;;
      --update-rancher)
        UPDATE_RANCHER=1
        shift
        ;;
      --no-pull)
        NO_PULL=1
        shift
        ;;
      --dir)
        shift
        INSTALL_DIR="${1:-}"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage
        exit 2
        ;;
    esac
  done

  if [ -z "${USERNAME}" ]; then
    echo "ERROR: --user is required." >&2
    usage
    exit 2
  fi
}

update_rancher_desktop_linux() {
  if ! is_linux; then return 0; fi

  if ! command -v rancher-desktop >/dev/null 2>&1; then
    msg "Rancher Desktop not found; skipping update."
    return 0
  fi

  local pkgtype=""
  if command -v apt-get >/dev/null 2>&1; then
    pkgtype="deb"
  elif command -v dnf >/dev/null 2>&1 || command -v rpm >/dev/null 2>&1; then
    pkgtype="rpm"
  else
    msg "No supported package manager found (need apt or rpm). Skipping Rancher Desktop update."
    return 0
  fi

  require_sudo
  require_cmd curl

  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64) arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
  esac

  msg "Checking latest Rancher Desktop release..."
  local tag asset_url
  tag="$(curl -fsSL https://api.github.com/repos/rancher-sandbox/rancher-desktop/releases/latest \
    | grep -m1 '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')"

  asset_url="$(curl -fsSL "https://api.github.com/repos/rancher-sandbox/rancher-desktop/releases/tags/${tag}" \
    | grep -Eo 'https://[^"]+\.(deb|rpm)' \
    | grep -E "${pkgtype}$" \
    | grep -E "${arch}" \
    | head -n1)"

  if [ -z "$asset_url" ]; then
    msg "Could not find matching ${pkgtype} asset for arch ${arch}. Skipping."
    return 0
  fi

  local tmp pkg
  tmp="$(mktemp -d)"
  pkg="${tmp}/rancher-desktop.${pkgtype}"
  curl -fsSL "$asset_url" -o "$pkg"

  msg "Updating Rancher Desktop to ${tag}..."
  if [ "$pkgtype" = "deb" ]; then
    sudo apt-get update
    sudo apt-get install -y "$pkg"
  else
    if command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y "$pkg"
    else
      sudo rpm -Uvh --replacepkgs "$pkg"
    fi
  fi
}

apply_configuration() {
  msg "Applying declarative configuration..."
  export BASE_TOOLING_USER="${USERNAME}"

  if is_darwin; then
    require_sudo
    nix build --impure "${INSTALL_DIR}#darwinConfigurations.${DARWIN_TARGET}.system"
    sudo ./result/sw/bin/darwin-rebuild switch --impure --flake "${INSTALL_DIR}#${DARWIN_TARGET}"
  else
    with_nix_profile_add_shim nix run github:nix-community/home-manager -- \
      switch \
      --impure \
      --flake "${INSTALL_DIR}#${USERNAME}@linux"
  fi
}

main() {
  parse_args "$@"

  msg "Base tooling update (Day-2) starting..."
  msg "Detected OS: $(uname -s) ($(uname -m))"
  msg "Using user: ${USERNAME}"
  msg "Repo dir: ${INSTALL_DIR}"

  if [ ! -d "${INSTALL_DIR}/.git" ]; then
    echo "ERROR: Repo not found at ${INSTALL_DIR}." >&2
    echo "Run install.sh first (Day-0)." >&2
    exit 1
  fi

  require_cmd git

  if [ "$NO_PULL" -eq 0 ]; then
    msg "Updating repo..."
    if [ -n "$(git -C "${INSTALL_DIR}" status --porcelain)" ]; then
      echo "ERROR: Working tree has uncommitted changes in ${INSTALL_DIR}." >&2
      echo "Commit/stash them, or re-run with --no-pull." >&2
      exit 1
    fi
    git -C "${INSTALL_DIR}" pull --rebase
  else
    msg "Skipping git pull (--no-pull)."
  fi

  if [ "$UPDATE_RANCHER" -eq 1 ]; then
    update_rancher_desktop_linux
  fi

  apply_configuration

  msg "Done."
}

main "$@"
