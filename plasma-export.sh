#!/usr/bin/env bash
# Plasma-Einstellungen zurück ins Repo synchronisieren.
#
# Du klickst in den Systemeinstellungen herum (overrideConfig = false, es wird
# dir nichts weggeräumt). Wenn dir das Ergebnis gefällt, exportiert dieses
# Skript den aktuellen Zustand, filtert Laufzeitmüll und Sensibles heraus und
# legt das Ergebnis zum Vergleich ab.
#
# Es schreibt NICHTS in plasma/*.nix — den Diff übernimmst du bewusst selbst.
set -euo pipefail

msg() { printf "\n\033[1;34m==>\033[0m %s\n" "$*"; }
warn() { printf "\n\033[1;33m!!\033[0m %s\n" "$*" >&2; }

OUT_DIR="${TMPDIR:-/tmp}/base-tooling-plasma-export"
mkdir -p "$OUT_DIR"
RAW="${OUT_DIR}/raw.nix"
CLEAN="${OUT_DIR}/filtered.nix"

msg "rc2nix ausführen"
nix run github:nix-community/plasma-manager#rc2nix > "$RAW"

# ── Filter ──────────────────────────────────────────────────────────
# Alles hier wird bewusst verworfen. Begründungen stehen in
# plasma/common.nix im Kopfkommentar.
DROP='khotkeysrc|katesearchplugin|katefilebrowserplugin|kateprojectplugin'
DROP+='|katesession|Last Session|Days Meta Infos|Save Meta Infos'
DROP+='|lastImageSave|lastVideoSave|translatedScreenshotsFolder|translatedScreencastsFolder'
DROP+='|usersWallpapers|Wallpaper/org.kde.image|plasmanotifyrc|ktrashrc'
DROP+='|ViewPropsTimestamp|ExtractDialog|exclude filters'
DROP+='|amarok\.|wacomtablet|control-center\.|khotkeys\.'
DROP+='|Tiling/|Desktops\.Id_|Desktops\.Name_|kactivitymanagerdrc|switch-to-activity'
DROP+='|update_info|AlreadyImported|dbVersion|Config Revision'

msg "Filtern"
grep -vE "$DROP" "$RAW" > "$CLEAN"

RAW_N=$(wc -l < "$RAW")
CLEAN_N=$(wc -l < "$CLEAN")
msg "$RAW_N Zeilen exportiert, $CLEAN_N übrig ($((RAW_N - CLEAN_N)) verworfen)"

# ── Restprüfung auf Sensibles ───────────────────────────────────────
LEFTOVER="$(grep -nE "${HOME}|/home/[a-z]" "$CLEAN" || true)"
if [ -n "$LEFTOVER" ]; then
  warn "Diese Zeilen enthalten noch absolute Home-Pfade — vor dem Committen prüfen:

$LEFTOVER"
fi

# Grober Hinweisgeber auf Arbeits- oder Projektnamen, die im letzten Export
# über die Kate-Suchhistorie mitgekommen waren.
SUSPECT="$(grep -niE 'service|projekt|project|kunde|client|intern' "$CLEAN" || true)"
if [ -n "$SUSPECT" ]; then
  warn "Verdächtig (könnten Projekt- oder Arbeitsbezüge sein), bitte durchsehen:

$SUSPECT"
fi

cat <<EOF

Ergebnis:
  ungefiltert : $RAW
  gefiltert   : $CLEAN

Nächster Schritt — Diff gegen die bestehende Basis, dann selektiv übernehmen:

  diff <(grep -oE '^\s+[a-zA-Z0-9."/ _-]+ =' "$CLEAN" | sort) \\
       <(grep -oE '^\s+[a-zA-Z0-9."/ _-]+ =' "$(dirname "\$0")/plasma/common.nix" | sort)

Geräteabhängiges gehört nach plasma/\$(hostname -s).nix, nicht nach
plasma/common.nix: Skalierung, Libinput-Geräte-IDs, Maustasten-Rebinds.
EOF
