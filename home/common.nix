{ config, pkgs, lib, username, ... }:

let
  homeDir =
    if pkgs.stdenv.isDarwin
    then /. + "/Users/${username}"
    else /. + "/home/${username}";
in
{
  xdg.enable = true;
  home.username = lib.mkForce username;
  home.homeDirectory = lib.mkForce homeDir;

  home.stateVersion = "24.11";

  programs.git = {
    enable = true;
    # Name + email are not stored in this repo.
    # install.sh writes ~/.gitconfig-identity once (name only).
    # Email is set per-repo: git config --local user.email "you@example.com"
    includes = [{ path = "~/.gitconfig-identity"; }];
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh";
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

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

      # ---- Quarkus CLI completion ----
      if command -v quarkus >/dev/null 2>&1; then
        autoload -Uz bashcompinit
        bashcompinit

        # Quarkus completion sometimes emits extra output -> keep it quiet
        source <(quarkus completion 2>/dev/null)
      fi
    '';
  };

  home.packages = with pkgs; [
    netbeans
    curl
    jq
    git
    gh
    devenv
    graphviz
    plantuml
    fontconfig
    graalvmPackages.graalvm-ce
    quarkus
    jbang
    slack
  ];
}
