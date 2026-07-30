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

  # ── KDE muss Nix- UND Flatpak-Apps sehen ────────────────────────────
  # Plasma sourct dieses Verzeichnis vor dem Session-Start. Ohne das Script
  # kennt KDE XDG_DATA_DIRS nicht und findet die Anwendungen nicht im
  # Anwendungsstarter.
  #
  # Zwei getrennte Baustellen im selben Script:
  #
  # 1. Nix — ohne die hm-session-vars fehlt ~/.nix-profile/share, dann taucht
  #    z.B. NetBeans nicht im Menue auf.
  #
  # 2. Flatpak — user-installierte Flatpaks legen ihre Desktop-Dateien unter
  #    ~/.local/share/flatpak/exports/share ab. Normalerweise ergaenzt
  #    /etc/profile.d/flatpak.sh diesen Pfad, aber eine Plasma-Session von
  #    SDDM laeuft nicht zwingend durch eine Login-Shell — dann greift das
  #    Script nie und GIMP, VLC, Inkscape und Steam sind installiert, aber
  #    im Menue unsichtbar.
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

      # Erst den Spec-Default setzen, damit /usr/share nicht verloren geht,
      # falls XDG_DATA_DIRS leer ist.
      : "''${XDG_DATA_DIRS:=/usr/local/share:/usr/share}"
      for _d in \
        "$HOME/.local/share/flatpak/exports/share" \
        /var/lib/flatpak/exports/share
      do
        case ":$XDG_DATA_DIRS:" in
          *":$_d:"*) ;;
          *) XDG_DATA_DIRS="$_d:$XDG_DATA_DIRS" ;;
        esac
      done
      unset _d
      export XDG_DATA_DIRS

      # plasma-manager ruft `qdbus` ohne Pfad und ohne deklarierte
      # Abhaengigkeit auf, um die Panel-Konfiguration an plasmashell zu
      # uebergeben:
      #   qdbus org.kde.plasmashell /PlasmaShell …evaluateScript "$(cat …)"
      #
      # Auf Ubuntu heisst das Binary im PATH aber `qdbus6`; das unter dem
      # Namen `qdbus` erreichbare liegt in /usr/lib/qt6/bin und ist nicht im
      # PATH. Ohne diesen Eintrag scheitert das Anwenden still mit
      # "qdbus: Kommando nicht gefunden" — das Panel bleibt unveraendert, und
      # zu sehen ist der Fehler nur, wenn man das Skript von Hand aufruft.
      #
      # Angehaengt, nicht vorangestellt: so ueberdecken die Qt-Werkzeuge in
      # diesem Verzeichnis nichts, was schon im PATH liegt.
      for _q in /usr/lib/qt6/bin /usr/lib/qt5/bin; do
        if [ -x "$_q/qdbus" ]; then
          case ":$PATH:" in
            *":$_q:"*) ;;
            *) PATH="$PATH:$_q" ;;
          esac
        fi
      done
      unset _q
      export PATH
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
