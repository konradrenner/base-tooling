{ config, pkgs, lib, ... }:

let
  sys = import ../system/packages.nix;
in
{
  imports = [ ../plasma/common.nix ];

  # ── Flatpak ─────────────────────────────────────────────────────────
  # Additive App-Schicht: die Menge ist deklariert, die Versionen floaten.
  #
  # uninstallUnmanaged = false ist Absicht und folgt derselben Philosophie
  # wie overrideConfig = false bei Plasma: deklarativer Boden, manuell
  # obendrauf. Was du in Discover installierst, bleibt erhalten.
  # Auf true gestellt würde jeder switch alles Nicht-Deklarierte entfernen.
  services.flatpak = {
    enable = true;
    uninstallUnmanaged = false;

    remotes = [{
      name = "flathub";
      location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
    }];

    packages = sys.flatpak.packages;

    update.auto = {
      enable = true;
      onCalendar = "weekly";
    };
  };

  # ── KDE muss die Nix-Apps sehen ─────────────────────────────────────
  # Plasma sourct dieses Verzeichnis vor dem Session-Start. Ohne das Script
  # kennt KDE XDG_DATA_DIRS nicht und findet keine Nix-installierten Apps
  # im Anwendungsstarter (betrifft z.B. NetBeans und Ancestris).
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

  # ── Session ─────────────────────────────────────────────────────────
  home.sessionVariables = {
    # Docker CE kommt aus apt; devenv-Shells sollen den Socket sehen.
    DOCKER_HOST = "unix:///var/run/docker.sock";

    # Für Electron-Anwendungen aus Nix (derzeit Winboat): nixpkgs-Wrapper
    # lesen diese Variablen und wählen damit die richtige Ozone-Plattform,
    # statt unter Wayland in XWayland zu landen.
    NIXOS_OZONE_WL = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
  };

  # Gleiches für direnv-/devenv-Shells, unabhängig von der Login-Shell.
  programs.direnv.stdlib = ''
    export DOCKER_HOST="unix:///var/run/docker.sock"
  '';
}
