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
    slack = "slack --no-sandbox --ozone-platform=x11";
    spotify = "spotify --no-sandbox --ozone-platform=x11";
  };

  home.packages = with pkgs; [
    vscode-runner
    vlc
    gimp
    spotify
    slack
    # Docker wird benötigt, da bestimmte Spezialsoftware (z.B. Winboat mit USB-Passthrough)
    # nicht mit Podman kompatibel ist und zwingend Docker CE voraussetzt.
    docker
    docker-compose
  ];

  xdg.desktopEntries."code" = {
    name = "Visual Studio Code";
    exec = "${pkgs.vscode}/bin/code --no-sandbox %F";
    icon = "vscode";
    terminal = false;
    categories = [ "Development" "IDE" ];
  };

  xdg.desktopEntries."slack" = {
    name = "Slack";
    exec = "${pkgs.slack}/bin/slack --no-sandbox --ozone-platform=x11 %U";
    icon = "slack";
    terminal = false;
    categories = [ "Network" "InstantMessaging" ];
    mimeType = [ "x-scheme-handler/slack" ];
  };

  xdg.desktopEntries."spotify" = {
    name = "Spotify";
    exec = "${pkgs.spotify}/bin/spotify --no-sandbox --ozone-platform=x11 %U";
    icon = "spotify";
    terminal = false;
    categories = [ "Audio" "Music" "Player" "AudioVideo" ];
    mimeType = [ "x-scheme-handler/spotify" ];
  };

  xdg.desktopEntries."netbeans" = {
    name = "Netbeans";
    exec = "${pkgs.netbeans}/bin/netbeans --fontsize 14";
    icon = "netbeans";
    terminal = false;
    categories = [ "Development" "IDE" ];
  };

  # KDE Plasma sourcet dieses Verzeichnis vor dem Session-Start.
  # Ohne dieses Script kennt KDE XDG_DATA_DIRS nicht und findet keine
  # Nix-installierten Apps im Anwendungsstarter.
  xdg.configFile."plasma-workspace/env/nix.sh" = {
    executable = true;
    text = ''
      #!/bin/sh
      if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
      fi
      if [ -e "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
        . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
      fi
    '';
  };

  home.sessionVariables = {
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    NIXOS_OZONE_WL = "1";
  };

  # Global direnv stdlib – Docker-Socket auch in devenv-Shells verfügbar
  # Docker wird benötigt, da bestimmte Spezialsoftware (z.B. Winboat mit USB-Passthrough)
  # nicht mit Podman kompatibel ist und zwingend Docker CE voraussetzt.
  programs.direnv.stdlib = ''
    export DOCKER_HOST="unix:///var/run/docker.sock"
  '';
}
