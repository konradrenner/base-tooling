{ config, pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    dotDir = config.home.homeDirectory;

    shellAliases = {
      netbeans = ''netbeans --userdir "$(pwd)/.netbeans" > /dev/null 2>&1 &'';
    };

    initContent = ''
      autoload -Uz vcs_info
      precmd() { vcs_info }

      zstyle ':vcs_info:git:*' formats ' (%b%u%c)'
      zstyle ':vcs_info:git:*' actionformats ' (%b|%a%u%c)'
      zstyle ':vcs_info:git:*' stagedstr '+'
      zstyle ':vcs_info:git:*' unstagedstr '*'
      zstyle ':vcs_info:git:*' check-for-changes true

      setopt PROMPT_SUBST
      PROMPT='%F{green}%n@%m%f:%F{blue}%~%f%F{yellow}$vcs_info_msg_0_%f%(!.#.$) '

      # ---- Quarkus CLI completion----
      if command -v quarkus >/dev/null 2>&1; then
        autoload -Uz bashcompinit
        bashcompinit

        # Quarkus completion sometimes emits extra output -> keep it quiet
        source <(quarkus completion 2>/dev/null)
      fi
    '';
  };

  home.sessionVariables = {
    CLICOLOR = "1";
    LSCOLORS = "GxFxCxDxBxegedabagaced";
  };
}
