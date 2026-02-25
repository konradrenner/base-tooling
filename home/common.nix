{ config, pkgs, lib, username, ... }:

let
  # Home Manager expects an absolute Nix *path* (not a string)
  homeDir =
    if pkgs.stdenv.isDarwin
    then /. + "/Users/${username}"
    else /. + "/home/${username}";
in
{
  home.username = lib.mkForce username;
  home.homeDirectory = lib.mkForce homeDir;

  # Set once when adopting Home Manager; don't change later.
  home.stateVersion = "24.11";

  programs.git.enable = true;

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # VS Code option rename fix:
  programs.vscode = {
    enable = true;
    profiles.default.extensions = pkgs.nix4vscode.forVscode [
      "ms-vscode-remote.remote-containers"
      "asciidoctor.asciidoctor-vscode"
      "jebbs.plantuml"
      "alphabotsec.vscode-eclipse-keybindings"
      "OleksandrHavrysh.intellij-formatter"
    ];
  };

  # Unified zsh on mac+linux, but with "Ubuntu bash-ish" prompt/colors
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    # silence warning and lock legacy behavior (home directory)
    dotDir = config.home.homeDirectory;

    # initExtra is deprecated -> initContent
    initContent = ''
      # history niceties
      setopt HIST_IGNORE_ALL_DUPS
      setopt HIST_REDUCE_BLANKS
      setopt SHARE_HISTORY
      setopt INC_APPEND_HISTORY

      export EDITOR=''${EDITOR:-code}

      # Colors
      autoload -Uz colors && colors

      # "Ubuntu bash-like" prompt:
      # green user@host : blue path $/# like bash
      PROMPT='%F{green}%n@%m%f:%F{blue}%~%f%# '

      # bash-ish completions feel a bit nicer
      zstyle ':completion:*' menu select
      zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
    '';
  };

  home.packages = with pkgs; [
    vscode
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
  ];
}
