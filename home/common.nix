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

  programs.git.enable = true;

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

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
    spotify
    quarkus
    jbang
    vlc
    gimp
  ];
}
