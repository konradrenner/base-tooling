{ config, pkgs, lib, profile, ... }:

# Bauform "notebook": Gerät mit Touchpad und internem Display.
# Sagt nichts über eine bestimmte Maschine oder ihren Hostnamen aus.

{
  imports = [ ../../plasma/notebook.nix ];

  # Platz für Pakete, die nur auf mobilen Geräten Sinn haben.
  # home.packages = with pkgs; [ ];
}
