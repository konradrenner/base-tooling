{ config, pkgs, lib, ... }:

# Plasma-Einstellungen für die Bauform "desktop": kein Touchpad, kein
# internes Display. Gilt auch für virtuelle Maschinen.
#
# Noch leer, und in vielen Fällen bleibt das auch so — ohne Touchpad und
# ohne internes Panel gibt es kaum Bauform-Abhängiges. Nach dem Einrichten
# mit plasma-export.sh exportieren und eintragen, falls nötig:
#
#   kdeglobals.KScreen.ScaleFactor        = 1.0;
#   kdeglobals.KScreen.ScreenScaleFactors = "DP-1=1;HDMI-A-1=1;";
#   kcminputrc."ButtonRebinds/Mouse".ExtraButton3 = "Key,Meta+G";
#
# Nicht eintragen: kwinrc "Tiling/<UUID>", kwinrc Desktops.Id_*,
# kactivitymanagerdrc — die hängen an UUIDs, die KDE bei jeder
# Neuinstallation neu vergibt.

{
  programs.plasma.configFile = {
    # Platzhalter, damit das Modul auswertbar bleibt.
  };
}
