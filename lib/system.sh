#!/usr/bin/env bash
# Gemeinsame Funktionen für bootstrap.sh und sync.sh.
# Wird erst nach dem Klonen des Repos gesourct.

msg() { printf "\n\033[1;34m==>\033[0m %s\n" "$*"; }
warn() { printf "\n\033[1;33m!!\033[0m %s\n" "$*" >&2; }
err() { printf "\n\033[1;31mFEHLER:\033[0m %s\n" "$*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1; }

ensure_sudo() {
  msg "sudo-Rechte werden benötigt, du wirst evtl. nach dem Passwort gefragt."
  sudo -v
}

# ── Layer-Prüfung ───────────────────────────────────────────────────
# apt und Flatpak müssen disjunkt sein, sonst gibt es doppelte
# Startmenü-Einträge oder verschattete Binaries im PATH.
check_layer_overlap() {
  local repo="$1"
  local apt_list flatpak_list overlap

  apt_list="$(nix eval --raw "${repo}#aptInstall" | tr ' ' '\n' | sort -u)"
  flatpak_list="$(nix eval --raw "${repo}#flatpakPackages" \
    | tr ' ' '\n' | awk -F. '{print tolower($NF)}' | sort -u)"

  overlap="$(comm -12 <(echo "$apt_list") <(echo "$flatpak_list") || true)"
  if [ -n "$overlap" ]; then
    warn "Paketname taucht in apt UND Flatpak auf:
$overlap
Prüfe die Listen in system/packages.nix."
  fi
}

# ── apt ─────────────────────────────────────────────────────────────
apt_repo_setup() {
  local repo="$1"
  msg "Fremd-apt-Repos einrichten (idempotent)"
  local setup
  setup="$(nix eval --raw "${repo}#aptRepoSetup")"
  bash -euo pipefail -c "$setup"
}

apt_install() {
  local repo="$1"
  local pkgs
  pkgs="$(nix eval --raw "${repo}#aptInstall")"

  msg "apt update"
  sudo apt-get update -y

  msg "apt install (${pkgs})"
  # shellcheck disable=SC2086
  sudo apt-get install -y $pkgs
}

# Purge mit Sicherheitsnetz: erst simulieren, und abbrechen falls apt mehr
# entfernen würde als deklariert. Kein `-y` ins Blaue.
apt_purge_checked() {
  local repo="$1"
  local declared installed=() sim removed extra p

  declared="$(nix eval --raw "${repo}#aptPurge")"

  for p in $declared; do
    if dpkg-query -W -f='${Status}' "$p" 2>/dev/null \
        | grep -q "install ok installed"; then
      installed+=("$p")
    fi
  done

  if [ ${#installed[@]} -eq 0 ]; then
    msg "Purge: nichts zu entfernen, alles schon weg."
    return 0
  fi

  msg "Purge simulieren: ${installed[*]}"
  if ! sim="$(sudo apt-get purge --simulate "${installed[@]}" 2>&1)"; then
    err "apt-get purge --simulate ist fehlgeschlagen:
$sim"
  fi

  removed="$(echo "$sim" | awk '/^Remv /{print $2}' | sort -u)"
  extra="$(comm -23 <(echo "$removed") \
                    <(printf '%s\n' "${installed[@]}" | sort -u) || true)"

  if [ -n "$extra" ]; then
    err "ABBRUCH — apt würde zusätzlich diese Pakete mitentfernen:

$extra

Nichts wurde verändert. Prüfe die purge-Liste in system/packages.nix.
Wenn das so gewollt ist, trage die Pakete dort mit ein."
  fi

  msg "Purge ausführen: ${installed[*]}"
  sudo apt-get purge -y "${installed[@]}"

  # autoremove läuft absichtlich NICHT automatisch — es würde die
  # --simulate-Prüfung umgehen. Bei Bedarf manuell:
  #   sudo apt-get autoremove --purge
  warn "Verwaiste Abhängigkeiten wurden nicht entfernt.
Falls gewünscht, prüfe manuell mit: sudo apt-get autoremove --purge --simulate"
}

# ── Gruppen und Login-Shell ─────────────────────────────────────────
ensure_groups() {
  local user="$1" g
  for g in docker libvirt kvm; do
    if getent group "$g" >/dev/null 2>&1; then
      if ! id -nG "$user" | tr ' ' '\n' | grep -qx "$g"; then
        msg "Füge '$user' zur Gruppe '$g' hinzu"
        sudo usermod -aG "$g" "$user"
        NEEDS_RELOGIN=1
      fi
    else
      warn "Gruppe '$g' existiert nicht — übersprungen."
    fi
  done
}

ensure_zsh_login_shell() {
  local user="$1" zsh_path
  # Muss eine System-Shell aus /etc/shells sein, kein Nix-Store-Pfad.
  zsh_path="$(command -v zsh || true)"
  case "$zsh_path" in
    /nix/store/*|"")
      zsh_path="/usr/bin/zsh"
      ;;
  esac

  if [ ! -x "$zsh_path" ]; then
    warn "zsh nicht unter $zsh_path gefunden — Login-Shell nicht geändert."
    return 0
  fi

  if ! grep -qx "$zsh_path" /etc/shells 2>/dev/null; then
    warn "$zsh_path steht nicht in /etc/shells — Login-Shell nicht geändert."
    return 0
  fi

  local current
  current="$(getent passwd "$user" | cut -d: -f7)"
  if [ "$current" != "$zsh_path" ]; then
    msg "Setze Login-Shell für '$user' auf $zsh_path (war: $current)"
    sudo chsh -s "$zsh_path" "$user"
    NEEDS_RELOGIN=1
  fi
}

# ── Home Manager ────────────────────────────────────────────────────
# Nutzt bewusst das in flake.lock gepinnte Home Manager, nicht
# `nix run github:nix-community/home-manager` — sonst würde die
# Home-Manager-Version bei jedem Lauf floaten.
#
# --impure ist nötig, weil username/homeDirectory über $USER und $HOME
# in den Flake kommen (siehe flake.nix). Die Paketauswahl bleibt davon
# unberührt und stammt vollständig aus flake.lock.
hm_switch() {
  local repo="$1" host="$2"
  local out="${TMPDIR:-/tmp}/base-tooling-hm-${host}"

  msg "Home-Manager-Konfiguration bauen (Profil: ${host})"
  nix build --impure -L \
    -o "$out" \
    "${repo}#homeConfigurations.${host}.activationPackage"

  msg "Aktivieren"
  HOME_MANAGER_BACKUP_EXT=hm-bak "${out}/activate"
}
