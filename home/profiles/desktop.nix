{ config, pkgs, lib, profile, ... }:

# Bauform "desktop": kein Touchpad, kein internes Display.
# Gilt auch für virtuelle Maschinen.

{
  imports = [ ../../plasma/desktop.nix ];

  # Platz für Pakete, die nur an stationären Geräten Sinn haben.
  # home.packages = with pkgs; [ ];
}
