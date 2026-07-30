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
PROFILE_ARG=""
PROFILE=""
NO_PULL=false
SKIP_APT=false
SKIP_FLATPAK_GC=false
NEEDS_RELOGIN=0

usage() {
  cat <<'USAGE'
Verwendung:
  sync.sh [--profile <name>] [--no-pull] [--skip-apt] [--skip-flatpak-gc]

  --profile <name>    Bauform-Profil erzwingen (notebook | desktop). Ohne
                      Angabe wird die Bauform über den DMI-Chassis-Typ
                      automatisch erkannt.
  --no-pull           Nicht aus dem Remote aktualisieren
  --skip-apt          apt-Layer überspringen, nur Nix + Plasma anwenden
  --skip-flatpak-gc   Ungenutzte Flatpak-Runtimes nicht entfernen.
                      Sinnvoll bei schmaler Leitung: ein entferntes Runtime
                      wird beim nächsten Bedarf neu geladen, und das sind
                      leicht mehrere Gigabyte.

Der Hostname der Maschine spielt keine Rolle und wird nicht verändert.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE_ARG="${2:-}"; shift 2 ;;
    --no-pull) NO_PULL=true; shift ;;
    --skip-apt) SKIP_APT=true; shift ;;
    --skip-flatpak-gc) SKIP_FLATPAK_GC=true; shift ;;
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

resolve_profile "$INSTALL_DIR" "$PROFILE_ARG"
check_layer_overlap "$INSTALL_DIR"

if [[ "$SKIP_APT" == true ]]; then
  warn "apt-Layer übersprungen (--skip-apt)."
else
  ensure_sudo
  apt_repo_setup "$INSTALL_DIR"
  apt_install "$INSTALL_DIR"
  apt_install_debs "$INSTALL_DIR"
  apt_purge_checked "$INSTALL_DIR"
  ensure_groups "$USER"
fi

hm_switch "$INSTALL_DIR" "$PROFILE"

# Bewusst NACH hm_switch, siehe Kommentar in lib/system.sh.
if [[ "$SKIP_APT" == false ]]; then
  ensure_zsh_login_shell "$USER"
fi

# Bewusst NACH hm_switch: erst ist der deklarierte Flatpak-Stand angewandt,
# danach steht fest, welche Runtimes wirklich niemand mehr braucht.
if [[ "$SKIP_FLATPAK_GC" == true ]]; then
  warn "Flatpak-Aufräumen übersprungen (--skip-flatpak-gc)."
else
  flatpak_gc
fi

msg "Fertig."
if [[ "$NEEDS_RELOGIN" -eq 1 ]]; then
  warn "Ab- und wieder anmelden nötig (Gruppen bzw. Login-Shell geändert)."
fi
