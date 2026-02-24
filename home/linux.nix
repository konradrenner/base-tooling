{ config, pkgs, username, ... }:

{
  imports = [ ./common.nix ];
  # Linux-specific Home Manager configuration

  programs.bash = {
    enable = true;
    enableCompletion = true;
  };

  # Optional baseline
  xdg.enable = true;
}
