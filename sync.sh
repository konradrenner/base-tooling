#!/usr/bin/env bash
# Day-2: Änderungen aus dem Repo anwenden.
#
#   ~/.base-tooling/sync.sh
#
# Aktualisiert NICHT die Nix-Versionen. Das ist Absicht — dafür bewusst:
#   nix flake update && git commit -am "flake inputs" && git push
# und danach auf beiden Maschinen sync.sh. So bleiben die gepinnten
# Versionen auf Notebook und Standpc deckungsgleich.
set -euo pipefail

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST=""
NO_PULL=false
SKIP_APT=false
NEEDS_RELOGIN=0

usage() {
  cat <<'USAGE'
Verwendung:
  sync.sh [--host <name>] [--no-pull] [--skip-apt]

  --host <name>   Profil überschreiben (Default: Hostname der Maschine)
  --no-pull       Nicht aus dem Remote aktualisieren
  --skip-apt      apt-Layer überspringen, nur Nix + Plasma anwenden
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --no-pull) NO_PULL=true; shift ;;
    --skip-apt) SKIP_APT=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf "Unbekanntes Argument: %s\n" "$1" >&2; usage; exit 1 ;;
  esac
done

# shellcheck source=lib/system.sh
. "${INSTALL_DIR}/lib/system.sh"

[[ "$(uname -s)" == "Linux" ]] || err "Dieses Setup ist nur für Linux."
[[ "${EUID}" -ne 0 ]] || err "Nicht als root ausführen."
[[ -n "${USER:-}" ]] || err "\$USER ist nicht gesetzt."
[[ -n "${HOME:-}" ]] || err "\$HOME ist nicht gesetzt."

require_cmd nix || err "nix nicht im PATH. Öffne ein neues Terminal, oder führe bootstrap.sh aus."

if [[ "$NO_PULL" == false ]]; then
  msg "Repo aktualisieren"
  git -C "$INSTALL_DIR" pull --ff-only
fi

[[ -n "$HOST" ]] || HOST="$(hostname -s)"

known="$(nix eval --raw "${INSTALL_DIR}#hostList")"
case " ${known} " in
  *" ${HOST} "*) msg "Profil: ${HOST}" ;;
  *) err "Kein Profil namens '${HOST}'.
Bekannte Profile: ${known}

Entweder --host <name> mit einem bekannten Profil aufrufen, oder
'${HOST}' anlegen: home/hosts/${HOST}.nix, plasma/${HOST}.nix und den
Namen in flake.nix bei 'hosts' ergänzen." ;;
esac

check_layer_overlap "$INSTALL_DIR"

if [[ "$SKIP_APT" == true ]]; then
  warn "apt-Layer übersprungen (--skip-apt)."
else
  ensure_sudo
  apt_repo_setup "$INSTALL_DIR"
  apt_install "$INSTALL_DIR"
  apt_purge_checked "$INSTALL_DIR"
  ensure_groups "$USER"
  ensure_zsh_login_shell "$USER"
fi

hm_switch "$INSTALL_DIR" "$HOST"

msg "Fertig."
if [[ "$NEEDS_RELOGIN" -eq 1 ]]; then
  warn "Ab- und wieder anmelden nötig (Gruppen bzw. Login-Shell geändert)."
fi
