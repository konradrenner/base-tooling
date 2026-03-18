{ config, pkgs, ... }:

{

  programs.vscode = {
    enable = true;

    profiles.default = {
      userSettings = {
        "window.titleBarStyle" = "native";
        "workbench.startupEditor" = "none";
        "update.showReleaseNotes" = false;
      };
    };

    profiles.default.extensions = pkgs.nix4vscode.forVscode [
      "ms-vscode-remote.remote-containers"
      "asciidoctor.asciidoctor-vscode"
      "jebbs.plantuml"
      "alphabotsec.vscode-eclipse-keybindings"
      "OleksandrHavrysh.intellij-formatter"
      "jnoortheen.nix-ide"
    ];
  };

  programs.zsh.shellAliases = {
    netbeans = ''netbeans --userdir "$(pwd)/.netbeans" --fontsize 14 > /dev/null 2>&1 &'';
    code = "code --no-sandbox --disable-setuid-sandbox --ozone-platform=wayland";
    docker = "podman";
    docker-compose = "podman-compose";
  };

  home.packages = with pkgs; [
    vscode-runner
    vlc
    gimp
    spotify
    podman
    podman-compose
  ];

  xdg.desktopEntries."code" = {
    name = "Visual Studio Code";
    exec = "${pkgs.vscode}/bin/code --no-sandbox %F";
    icon = "vscode";
    terminal = false;
    categories = [ "Development" "IDE" ];
  };

  xdg.desktopEntries."netbeans" = {
    name = "Netbeans";
    exec = "${pkgs.netbeans}/bin/netbeans --fontsize 14";
    icon = "netbeans";
    terminal = false;
    categories = [ "Development" "IDE" ];
  };

  home.sessionVariables = {
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    NIXOS_OZONE_WL = "1";
    DOCKER_HOST = "unix://$XDG_RUNTIME_DIR/podman/podman.sock";
  };

  # Global direnv stdlib – DOCKER_HOST auch in devenv-Shells gesetzt
  programs.direnv.stdlib = ''
    export DOCKER_HOST="unix://''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/podman/podman.sock"
  '';
}
