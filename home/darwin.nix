{ config, pkgs, ... }:

{
  xdg.enable = true;

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    dotDir = config.home.homeDirectory;

    initContent = ''
      setopt HIST_IGNORE_ALL_DUPS
      setopt HIST_REDUCE_BLANKS
      setopt SHARE_HISTORY
      setopt INC_APPEND_HISTORY

      export EDITOR=''${EDITOR:-code}

      autoload -Uz colors && colors

      PROMPT='%F{green}%n@%m%f:%F{blue}%~%f%(#.#.$) '

      zstyle ':completion:*' menu select
      zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
    '';
  };

  home.sessionVariables = {
    CLICOLOR = "1";
    LSCOLORS = "GxFxCxDxBxegedabagaced";
  };
}
