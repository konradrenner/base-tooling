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

# ── appletsrc aufbereiten ────────────────────────────────────────────
# rc2nix exportiert die appletsrc NICHT — Panel-Layout, Desktop-Widgets und
# ItemGeometries fehlen im rc2nix-Export komplett. Deshalb hier eine eigene,
# diffbare Sicht auf die appletsrc, ohne Laufzeitzustand (Dialog*/popup*)
# und ohne Aktivitäts-UUIDs. Übernahmeziel in plasma/*.nix:
#   ItemGeometries-<WxH>=Applet-<id>:x,y,w,h,0  -> desktop.widgets position/size
#   [Containments][..][General] AppletOrder    -> panels[].widgets Reihenfolge
#   [Containments][..][Applets][..] plugin     -> panels[].widgets / desktop.widgets name
#   [..][Applets][..][Configuration][Gruppe]   -> widget config.<Gruppe>
msg "appletsrc aufbereiten (Panel/Desktop-Widgets)"
APPLETSRC="${HOME}/.config/plasma-org.kde.plasma.desktop-appletsrc"
APP_OUT="${OUT_DIR}/appletsrc.txt"
{
  echo "# ItemGeometries-<WxH> = Applet-<id>:x,y,w,h,0  -> desktop.widgets position/size"
  grep -E '^ItemGeometries' "$APPLETSRC" 2>/dev/null || true
  echo
  echo "# Containments/Applets/Configuration -> panels / desktop.widgets"
  awk '
    /^\[/ { print; next }
    /^ItemGeometries/ { next }
    /^(DialogHeight|DialogWidth|popupHeight|popupWidth|activityId)=/ { next }
    { print }
  ' "$APPLETSRC" 2>/dev/null || true
} > "$APP_OUT"

# ── Restprüfung auf Sensibles ───────────────────────────────────────
LEFTOVER="$(grep -nE "${HOME}|/home/[a-z]" "$CLEAN" "$APP_OUT" 2>/dev/null || true)"
if [ -n "$LEFTOVER" ]; then
  warn "Diese Zeilen enthalten noch absolute Home-Pfade — vor dem Committen prüfen:

$LEFTOVER"
fi

# Grober Hinweisgeber auf Projektnamen. Solche Werte kommen typischerweise
# über Such- und Ersetzungshistorien in den Export.
SUSPECT="$(grep -niE 'service|projekt|project|kunde|client|intern' "$CLEAN" || true)"
if [ -n "$SUSPECT" ]; then
  warn "Verdächtig (könnten Projektbezüge sein), bitte durchsehen:

$SUSPECT"
fi

cat <<EOF

Ergebnis:
  ungefiltert : $RAW
  gefiltert   : $CLEAN
  appletsrc   : $APP_OUT   (rc2nix exportiert die appletsrc nicht; Kopfkommentar
                            dort erklärt die Übernahme nach panels / desktop.widgets)

Nächster Schritt — Diff gegen die bestehende Basis, dann selektiv übernehmen:

  diff <(grep -oE '^\s+[a-zA-Z0-9."/ _-]+ =' "$CLEAN" | sort) \\
       <(grep -oE '^\s+[a-zA-Z0-9."/ _-]+ =' "$(dirname "\$0")/plasma/common.nix" | sort)

Bauform-Abhängiges gehört nach plasma/notebook.nix bzw. plasma/desktop.nix,
nicht nach plasma/common.nix: Skalierung, Libinput-Geräte-IDs,
Maustasten-Rebinds.
EOF
