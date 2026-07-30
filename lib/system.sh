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

# ── Profil-Erkennung ────────────────────────────────────────────────
# Ein Profil beschreibt ausschliesslich die Hardware-Bauform:
#   notebook - hat Touchpad und internes Display mit eigener Skalierung
#   desktop  - hat beides nicht (gilt auch für VMs)
#
# Der Hostname spielt dabei bewusst keine Rolle und wird von diesen
# Skripten nie verändert. Er ist Sache des Systems.
#
# Gibt den Profilnamen aus, oder eine leere Zeichenkette, wenn die Bauform
# nicht bestimmbar ist. Dann muss --profile explizit mitgegeben werden.
detect_profile() {
  local chassis=""

  # DMI-Chassis-Typ ist die verlässlichste Quelle. Mögliche Werte:
  # desktop, laptop, convertible, tablet, handset, server, vm, container, ...
  if require_cmd hostnamectl; then
    chassis="$(hostnamectl chassis 2>/dev/null || true)"
  fi

  # Fallback ohne systemd-Auskunft: ein Akku bedeutet mobiles Gerät.
  if [ -z "$chassis" ]; then
    if compgen -G "/sys/class/power_supply/BAT*" > /dev/null 2>&1; then
      chassis="laptop"
    fi
  fi

  case "$chassis" in
    laptop | convertible | tablet | handset) echo "notebook" ;;
    desktop | server | vm | container) echo "desktop" ;;
    *) echo "" ;;
  esac
}

# Profil bestimmen und gegen die Liste im Flake prüfen.
# Setzt die globale Variable PROFILE. Verändert nichts am System.
resolve_profile() {
  local repo="$1" explicit="${2:-}"
  local known source

  known="$(nix eval --raw "${repo}#profileList")"

  if [ -n "$explicit" ]; then
    PROFILE="$explicit"
    source="explizit über --profile"
  else
    PROFILE="$(detect_profile)"
    source="aus der Bauform erkannt"
    if [ -z "$PROFILE" ]; then
      err "Die Hardware-Bauform liess sich nicht bestimmen.

Bekannte Profile: ${known}

Bitte explizit angeben, zum Beispiel:
    --profile desktop

Es wurde nichts verändert."
    fi
  fi

  case " ${known} " in
    *" ${PROFILE} "*)
      msg "Profil: ${PROFILE} (${source})"
      ;;
    *)
      err "Kein Profil namens '${PROFILE}'.
Bekannte Profile: ${known}

Es wurde nichts verändert.

Ein neues Profil braucht drei Stellen:
    1. home/profiles/${PROFILE}.nix
    2. plasma/${PROFILE}.nix
    3. in flake.nix bei 'profiles' den Namen ergänzen"
      ;;
  esac
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

# ── Flatpak aufräumen ───────────────────────────────────────────────
# Entfernt Runtimes und Extensions, die von keiner installierten Anwendung
# mehr referenziert werden.
#
# Warum das hier automatisch läuft, `apt autoremove` aber nicht: die
# Risikoprofile sind verschieden. apt kennt Kernel, Treiber und den halben
# Desktop, ein falsches autoremove zerlegt das System — deshalb dort nur
# manuell und simuliert. `flatpak uninstall --unused` wirkt ausschliesslich
# innerhalb der Flatpak-Welt und fasst per Definition nur Refs an, die von
# keiner installierten App gebraucht werden. Es kann weder eine App noch
# das System brechen.
#
# Hauptquelle des Zuwachses sind Runtime-Versionswechsel: aktualisiert eine
# App auf ein neueres Runtime, bleibt das alte als ungenutzt zurück. Genau
# das wird hier eingesammelt.
#
# Gezielt --user, weil nix-flatpak als home-manager-Modul die
# user-Installation verwaltet. Die system-Installation (z.B. was Discover
# dort ablegt) bleibt unberührt — das räumt dieses Skript nicht auf, weil es
# sie auch nicht verwaltet.
#
# Einen --dry-run kennt `flatpak uninstall` nicht, daher wird die Ausgabe
# mitgeschrieben und gemeldet.
flatpak_gc() {
  if ! require_cmd flatpak; then
    warn "flatpak nicht im PATH — Aufräumen übersprungen."
    return 0
  fi

  # nix-flatpak installiert über einen systemd-User-Service. Schlägt der fehl,
  # sind die deklarierten Apps nicht da, ihre Runtimes gelten damit als
  # ungenutzt — und ein Aufräumen würde genau das löschen, was der nächste
  # Versuch wieder braucht. Mehrere Gigabyte Neuladen pro Durchlauf.
  if require_cmd systemctl \
     && systemctl --user is-failed --quiet flatpak-managed-install.service 2>/dev/null; then
    warn "flatpak-managed-install.service ist fehlgeschlagen.
Die deklarierten Flatpaks sind vermutlich nicht installiert, deshalb wird
NICHT aufgeräumt — sonst würden Runtimes entfernt, die gleich wieder
gebraucht werden.

Ursache ansehen mit:
  systemctl --user status flatpak-managed-install.service
  journalctl --user -u flatpak-managed-install.service -n 50 --no-pager"
    return 0
  fi

  msg "Ungenutzte Flatpak-Runtimes entfernen (user-Installation)"

  local out
  if ! out="$(flatpak uninstall --user --unused --noninteractive 2>&1)"; then
    # Aufräumen ist Kür, kein Grund den Lauf abzubrechen.
    warn "flatpak uninstall --unused ist fehlgeschlagen, wird ignoriert:
${out}"
    return 0
  fi

  if [ -n "${out//[[:space:]]/}" ]; then
    printf "%s\n" "$out"
  else
    msg "Nichts zu entfernen."
  fi
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

# WICHTIG: Diese Funktion darf erst NACH hm_switch aufgerufen werden.
# Wird zsh zur Login-Shell gemacht, bevor Home Manager die Konfiguration
# angelegt hat, und schlaegt Home Manager dann fehl, landet man in einer
# nackten zsh und bekommt zsh-newuser-install vorgesetzt.
ensure_zsh_login_shell() {
  local user="$1" zsh_path

  # Zweite Absicherung gegen genau dieses Szenario: ohne Konfiguration
  # wird die Login-Shell nicht umgestellt.
  if [ ! -e "${HOME}/.zshrc" ]; then
    warn "~/.zshrc existiert nicht — Login-Shell bleibt unverändert.
Home Manager hat die Shell-Konfiguration offenbar nicht angelegt.
Ohne sie würde zsh dich mit zsh-newuser-install begrüssen."
    return 0
  fi

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
  local repo="$1" profile="$2"
  local out="${TMPDIR:-/tmp}/base-tooling-hm-${profile}"

  msg "Home-Manager-Konfiguration bauen (Profil: ${profile})"
  nix build --impure -L \
    -o "$out" \
    "${repo}#homeConfigurations.${profile}.activationPackage"

  msg "Aktivieren"
  HOME_MANAGER_BACKUP_EXT=hm-bak "${out}/activate"
}
