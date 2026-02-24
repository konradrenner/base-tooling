{ config, pkgs, username, ... }:

{
  imports = [ ./common.nix ];

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    initExtra = ''
      setopt HIST_IGNORE_ALL_DUPS
      setopt HIST_REDUCE_BLANKS
      export EDITOR=${EDITOR:-code}
    '';
  };

  xdg.enable = true;
}
