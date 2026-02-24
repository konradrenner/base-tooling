{ config, pkgs, username, ... }:

let
  homeDir =
    if pkgs.stdenv.isDarwin
    then "/Users/${username}"
    else "/home/${username}";
in
{
  home.username = username;
  home.homeDirectory = homeDir;

  home.stateVersion = "24.11";

  # -----------------
  # Base CLI tooling
  # -----------------
  programs.git.enable = true;

  # direnv is also enabled in per-OS modules to ensure shell hooks, but keeping it
  # here makes it available on both platforms.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # VS Code (editor) + extensions (installed declaratively via nix4vscode overlay)
  programs.vscode = {
    enable = true;

    # VS Code Marketplace extensions (IDs)
    extensions = pkgs.nix4vscode.forVscode [
      # Dev Containers
      "ms-vscode-remote.remote-containers"

      # Docs/Diagrams
      "asciidoctor.asciidoctor-vscode"
      "jebbs.plantuml"

      # Keymaps / formatting
      "alphabotsec.vscode-eclipse-keybindings"
      "OleksandrHavrysh.intellij-formatter"
    ];
  };

  # -----------------
  # Packages
  # -----------------
  home.packages = with pkgs; [
    # IDEs
    vscode
    netbeans

    # Essentials
    curl
    git

    # Dev env tooling
    devenv

    # Diagram + rendering helpers
    graphviz
    plantuml
    fontconfig

    # Java
    graalvmPackages.graalvm-ce

    # Optional: keep installed even if Rancher Desktop is the primary engine
    podman-desktop
  ];
}
