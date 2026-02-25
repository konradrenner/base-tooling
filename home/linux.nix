{ config, pkgs, ... }:

{
  xdg.enable = true;

  # Optional: keep bash available (some servers/scripts expect it)
  programs.bash.enable = true;
}
