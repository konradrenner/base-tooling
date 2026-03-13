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
    quarkus
    jbang
  ];
}
