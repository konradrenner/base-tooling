{ config, pkgs, lib, ... }:

# Maschinenspezifische Plasma-Einstellungen für den Standpc.
#
# Noch leer: für dieses Gerät liegt kein rc2nix-Export vor. Nach dem ersten
# Einrichten mit plasma-export.sh exportieren und die gerätespezifischen
# Blöcke hier eintragen — typischerweise:
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
