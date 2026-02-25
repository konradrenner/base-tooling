{ config, pkgs, ... }:

{
  xdg.enable = true;

  # macOS ls colors
  home.sessionVariables = {
    CLICOLOR = "1";
    # classic-ish color scheme
    LSCOLORS = "GxFxCxDxBxegedabagaced";
  };
}
