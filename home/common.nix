{ config, pkgs, username, ... }:

let
  # Must be an absolute *path* (not just a string) to satisfy HM type checks.
  homeDir =
    if pkgs.stdenv.isDarwin
    then /. + "/Users/${username}"
    else /. + "/home/${username}";
in
{
  home.username = username;
  home.homeDirectory = homeDir;

  # Set once when adopting Home Manager; don't change later.
  home.stateVersion = "24.11";

  programs.git.enable = true;

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.vscode = {
    enable = true;

    # VS Code Marketplace extensions (via nix4vscode overlay)
    extensions = pkgs.nix4vscode.forVscode [
      "ms-vscode-remote.remote-containers"
      "asciidoctor.asciidoctor-vscode"
      "jebbs.plantuml"
      "alphabotsec.vscode-eclipse-keybindings"
      "OleksandrHavrysh.intellij-formatter"
    ];
  };

  home.packages = with pkgs; [
    # IDEs / Editor
    vscode
    netbeans

    # Essentials
    curl
    git

    # Dev env tooling
    devenv

    # Diagramming
    graphviz
    plantuml
    fontconfig

    # Java
    graalvmPackages.graalvm-ce

    # Optional
    podman-desktop
  ];
}
