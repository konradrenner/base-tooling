#!/usr/bin/env bash
# Day-0: frisch installiertes TuxedoOS in einen fertigen Arbeitsplatz überführen.
#
#   curl -fsSL https://raw.githubusercontent.com/konradrenner/base-tooling/main/bootstrap.sh \
#     | bash
#
# Username und Home kommen aus $USER/$HOME und stehen nicht im Repo.
# Der Hostname wird nicht gelesen und nicht verändert.
set -euo pipefail

REPO_URL="https://github.com/konradrenner/base-tooling.git"
INSTALL_DIR="${HOME}/.base-tooling"
PROFILE_ARG=""
PROFILE=""
NO_PULL=false
SKIP_APT=false
NEEDS_RELOGIN=0

usage() {
  cat <<'USAGE'
Verwendung:
  bootstrap.sh [--profile <name>] [--dir <pfad>] [--no-pull] [--skip-apt]

  --profile <name>  Bauform-Profil erzwingen (notebook | desktop).
                    Normalerweise nicht nötig: die Bauform wird über den
                    DMI-Chassis-Typ automatisch erkannt. Nur angeben, wenn
                    die Erkennung fehlschlägt oder man sie übersteuern will.
  --dir <pfad>      Zielverzeichnis des Repos (Default: ~/.base-tooling)
  --no-pull         Vorhandenes Repo nicht aktualisieren
  --skip-apt        apt-Layer überspringen (nur Nix + Plasma anwenden)

Ein Profil beschreibt ausschliesslich die Hardware-Bauform:
  notebook  Touchpad und internes Display mit eigener Skalierung
  desktop   beides nicht — gilt auch für virtuelle Maschinen

Der Hostname der Maschine hat damit nichts zu tun und wird von diesem
Skript weder gelesen noch verändert.

Username und Home-Verzeichnis werden aus $USER und $HOME gelesen.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE_ARG="${2:-}"; shift 2 ;;
    --dir) INSTALL_DIR="${2:-}"; shift 2 ;;
    --no-pull) NO_PULL=true; shift ;;
    --skip-apt) SKIP_APT=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf "Unbekanntes Argument: %s\n" "$1" >&2; usage; exit 1 ;;
  esac
done

# ── Vorbedingungen ──────────────────────────────────────────────────
pre_msg() { printf "\n==> %s\n" "$*"; }
pre_err() { printf "\nFEHLER: %s\n" "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Linux" ]] || pre_err "Dieses Setup ist nur für Linux."
[[ "${EUID}" -ne 0 ]] || pre_err "Nicht als root ausführen. Das Skript ruft sudo selbst auf."
[[ -n "${USER:-}" ]] || pre_err "\$USER ist nicht gesetzt."
[[ -n "${HOME:-}" ]] || pre_err "\$HOME ist nicht gesetzt."

pre_msg "Benutzer: ${USER}   Home: ${HOME}"

ensure_git() {
  command -v git >/dev/null 2>&1 && return 0
  pre_msg "git installieren"
  sudo apt-get update -y
  sudo apt-get install -y git ca-certificates curl
}

ensure_nix() {
  if command -v nix >/dev/null 2>&1; then
    pre_msg "Nix ist bereits installiert."
    return 0
  fi

  pre_msg "Nix installieren (Determinate Systems Installer)"
  sudo -v
  curl -fsSL https://install.determinate.systems/nix \
    | sh -s -- install linux --determinate --no-confirm

  # Nix in DIESER Shell verfügbar machen (wichtig bei curl | bash).
  if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi

  command -v nix >/dev/null 2>&1 \
    || pre_err "nix ist nach der Installation nicht im PATH. Öffne ein neues Terminal und starte bootstrap.sh erneut."
}

ensure_flakes() {
  pre_msg "nix-command und flakes aktivieren (idempotent)"
  mkdir -p "${HOME}/.config/nix"
  local conf="${HOME}/.config/nix/nix.conf"
  touch "$conf"
  if ! grep -q 'experimental-features' "$conf"; then
    printf "experimental-features = nix-command flakes\n" >> "$conf"
  fi
}

ensure_repo() {
  if [[ -d "${INSTALL_DIR}/.git" ]]; then
    if [[ "$NO_PULL" == true ]]; then
      pre_msg "Repo vorhanden, --no-pull gesetzt."
    else
      pre_msg "Repo aktualisieren: ${INSTALL_DIR}"
      git -C "$INSTALL_DIR" pull --ff-only
    fi
  else
    ensure_git
    pre_msg "Repo klonen nach ${INSTALL_DIR}"
    git clone "$REPO_URL" "$INSTALL_DIR"
  fi
}

ensure_nix
ensure_flakes
ensure_repo

# Ab hier stehen die gemeinsamen Funktionen zur Verfügung.
# shellcheck source=lib/system.sh
. "${INSTALL_DIR}/lib/system.sh"

# ── Profil bestimmen ────────────────────────────────────────────────
# Setzt PROFILE. Liest den Hostnamen nicht und verändert ihn nicht.
resolve_profile "$INSTALL_DIR" "$PROFILE_ARG"
check_layer_overlap "$INSTALL_DIR"

# ── apt-Layer ───────────────────────────────────────────────────────
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

# ── Nix-Layer ───────────────────────────────────────────────────────
hm_switch "$INSTALL_DIR" "$PROFILE"

# ── Abschluss ───────────────────────────────────────────────────────
msg "Fertig."

cat <<EOF

Noch von Hand zu tun — das lässt sich nicht automatisieren:

  * Winboat einmal starten; es lädt beim ersten Lauf das Windows-Image.
    Das .deb ist nicht Teil des apt-Repos, siehe README.
  * KeePassXC-Browser-Extension in Firefox/Chrome installieren.
  * Nextcloud-Client anmelden.
  * Kontact-Konten einrichten.
  * Ancestris: Hash in pkgs/ancestris.nix eintragen, dann die Zeile in
    home/common.nix einkommentieren (siehe README).

EOF

if [[ "$NEEDS_RELOGIN" -eq 1 ]]; then
  warn "Ab- und wieder anmelden ist nötig:
Gruppenmitgliedschaften, Login-Shell und die Plasma-Konfiguration
werden erst beim nächsten Session-Start wirksam."
else
  msg "Melde dich einmal ab und wieder an, damit Plasma die neue Konfiguration liest."
fi
