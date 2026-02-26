{ config, pkgs, ... }:

let
  vscodeWayland = pkgs.symlinkJoin {
    name = "vscode-wayland";
    paths = [ pkgs.vscode ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/code" \
        --add-flags "--disable-setuid-sandbox" \
        --add-flags "--enable-features=UseOzonePlatform" \
        --add-flags "--ozone-platform=wayland"
    '';
  };
in
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    dotDir = config.home.homeDirectory;

    shellAliases = {
      netbeans = ''netbeans --userdir "$(pwd)/.netbeans" --fontsize 14 > /dev/null 2>&1 &'';
    };

    initContent = ''
      autoload -Uz vcs_info
      precmd() { vcs_info }

      zstyle ':vcs_info:git:*' formats ' (%b%u%c)'
      zstyle ':vcs_info:git:*' actionformats ' (%b|%a%u%c)'
      zstyle ':vcs_info:git:*' stagedstr '+'
      zstyle ':vcs_info:git:*' unstagedstr '*'

      setopt PROMPT_SUBST
      PROMPT='%F{green}%n@%m%f:%F{blue}%~%f%F{yellow}$vcs_info_msg_0_%f%(!.#.$) '

      # Quarkus autocomplete
      if command -v quarkus >/dev/null 2>&1; then
        source <(quarkus completion zsh)
      fi
    '';
  };

  programs.vscode = {
    enable = true;
    package = vscodeWayland;
  };

  # optional, aber oft sinnvoll auf Wayland:
  home.sessionVariables = {
    ELECTRON_OZONE_PLATFORM_HINT = "wayland";
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
