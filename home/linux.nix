{ config, pkgs, ... }:


{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    dotDir = config.home.homeDirectory;

    shellAliases = {
      netbeans = ''netbeans --userdir "$(pwd)/.netbeans" --fontsize 14 > /dev/null 2>&1 &'';
      code = "code --no-sandbox --disable-setuid-sandbox --ozone-platform=wayland";
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

  home.packages = with pkgs; [
    vscode-runner
    vlc
  ];

  home.sessionVariables = {
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    NIXOS_OZONE_WL = "1";
    XDG_DATA_DIRS = "$HOME/.nix-profile/share:/nix/var/nix/profiles/default/share:$XDG_DATA_DIRS";
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
