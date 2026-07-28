{ config, pkgs, lib, hostname, ... }:

{
  imports = [ ../../plasma/desktop.nix ];

  # Platz für Pakete, die es nur am Standpc geben soll.
  # home.packages = with pkgs; [ ];
}
