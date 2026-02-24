{ config, pkgs, ... }:

{
  # Linux-specific Home Manager configuration

  # Keep Bash as default shell on Linux
  programs.bash = {
    enable = true;
    enableCompletion = true;
  };

  # Ensure direnv hook is enabled for bash
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # Optional: basic XDG defaults (safe baseline)
  xdg.enable = true;

  # You can extend this file later with Linux-only packages or settings
  # (e.g. additional CLI tools, desktop integrations, etc.)
}
