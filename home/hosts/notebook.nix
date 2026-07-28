{ config, pkgs, lib, hostname, ... }:

{
  imports = [ ../../plasma/notebook.nix ];

  # Platz für Pakete, die es nur auf dem Notebook geben soll.
  # home.packages = with pkgs; [ ];
}
