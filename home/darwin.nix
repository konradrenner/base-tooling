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
      # Enable vcs_info
      autoload -Uz vcs_info
      precmd() { vcs_info }

      # Configure git format
      zstyle ':vcs_info:git:*' formats ' (%b%u%c)'
      zstyle ':vcs_info:git:*' actionformats ' (%b|%a%u%c)'
      zstyle ':vcs_info:git:*' stagedstr '+'
      zstyle ':vcs_info:git:*' unstagedstr '*'

      # Prompt
      setopt PROMPT_SUBST
      PROMPT='%F{green}%n@%m%f:%F{blue}%~%f%F{yellow}${vcs_info_msg_0_}%f%(!.#.$) '
    '';
  };

  home.sessionVariables = {
    CLICOLOR = "1";
    LSCOLORS = "GxFxCxDxBxegedabagaced";
  };
}
