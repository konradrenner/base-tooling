{ config, pkgs, lib, ... }:

# Plasma-Einstellungen für die Bauform "notebook": Geräte mit Touchpad und
# internem Display. Das ist der einzige Grund, warum es überhaupt zwei
# Profile gibt — mit dem Hostnamen der Maschine hat es nichts zu tun.
#
# Werte aus dem rc2nix-Export übernommen (eDP-1 ist das interne Panel).
#
# Absichtlich NICHT hier eingefroren, weil KDE sie selbst erzeugt und sie
# an UUIDs hängen, die pro Neuinstallation neu vergeben werden:
#   * kwinrc "Tiling/<UUID>"      - Kachel-Layouts pro Bildschirm/Desktop
#   * kwinrc Desktops.Id_*        - UUIDs der virtuellen Desktops
#   * kactivitymanagerdrc         - Activity-UUID
# Wenn du Kachel-Layouts festhalten willst, exportiere sie nach dem
# Einrichten mit plasma-export.sh und trage sie hier ein.

{
  programs.plasma.configFile = {
    # ── Skalierung ────────────────────────────────────────────────────
    # eDP-1 = internes Notebook-Panel, DP-5/DP-8 = Dock-Ausgänge.
    kdeglobals.KScreen.ScaleFactor = 1.5;
    kdeglobals.KScreen.ScreenScaleFactors = "eDP-1=1.5;DP-5=1.5;DP-8=1.5;";
    kdeglobals.KScreen.XwaylandClientsScale = false;

    # ── Touchpad ──────────────────────────────────────────────────────
    # Der Schlüssel enthält die Libinput-Geräte-ID und gilt nur für dieses
    # Gerät. Am Standpc existiert er nicht.
    kcminputrc."Libinput/2362/597/UNIW0001:00 093A:0255 Touchpad".NaturalScroll = true;
    kcminputrc."Libinput/2362/597/UNIW0001:00 093A:0255 Touchpad".TapToClick = true;

    # ── Zusatztasten der Maus ─────────────────────────────────────────
    # Gilt nur, solange dieselbe Maus angeschlossen ist.
    kcminputrc."ButtonRebinds/Mouse".ExtraButton3 = "Key,Meta+G";
    kcminputrc."ButtonRebinds/Mouse".ExtraButton4 = "Key,Alt+F1";
  };
}
