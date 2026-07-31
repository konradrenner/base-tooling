{ config, pkgs, lib, ... }:

let
  sys = import ../system/packages.nix;
in
{
  imports = [ ../plasma/common.nix ];

  # ── systemd-User-Units nicht abwarten ───────────────────────────────
  # Home Manager startet am Ende der Aktivierung die geänderten
  # systemd-User-Units und wartet per sd-switch synchron auf ihr Ende.
  # nix-flatpaks Installationsdienst ist aber Type=oneshot und lädt auf einem
  # frischen System mehrere Gigabyte — damit läuft die Aktivierung zwangsläufig
  # in den Timeout und bricht ab:
  #
  #   Starting units: flatpak-managed-install.service
  #   Error: Error switching systemd units
  #     1: timed out waiting on channel
  #
  # Und weil bootstrap.sh mit `set -e` läuft, riss das den gesamten Lauf mit,
  # obwohl Profilgeneration und Dateiverknüpfungen bereits angelegt waren.
  #
  # "suggest" heisst: Home Manager verwaltet den Unit-Zustand nicht, sondern
  # nennt nur, was zu starten wäre. Die Units haben WantedBy=default.target
  # und einen Timer, laufen also spätestens beim nächsten Login von selbst —
  # und bootstrap.sh/sync.sh stossen den Dienst zusätzlich mit --no-block an.
  #
  # Die Reichweite ist genau ein Dienst: nix-flatpak ist die einzige Quelle
  # von systemd-User-Units in dieser Konfiguration.
  systemd.user.startServices = "suggest";

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
      # Auf Ubuntu ist das aus zwei Gruenden kaputt, und die Faelle
      # unterscheiden sich je nach Maschine:
      #
      #   a) `qdbus` fehlt ganz. Das Binary heisst `qdbus6`, das unter dem
      #      Namen `qdbus` erreichbare liegt in /usr/lib/qt6/bin.
      #   b) `/usr/bin/qdbus` existiert, gehoert aber dem Dispatcher
      #      `qtchooser` und scheitert mit einer Meldung der Form
      #        qdbus: could not find a Qt installation of
      #      gefolgt von zwei Apostrophen.
      #
      #      Die werden hier bewusst nicht ausgeschrieben: zwei Apostrophe
      #      beenden einen mehrzeiligen Nix-String, der Kommentar wuerde also
      #      den Shell-Block mittendrin zerschneiden.
      #
      # Fall (b) ist der Grund, warum ein blosses Anhaengen von
      # /usr/lib/qt6/bin an den PATH nicht reicht: der kaputte Stub liegt
      # weiter vorne und gewinnt.
      #
      # Loesung ohne Kollateralschaden: ein Verzeichnis, das AUSSCHLIESSLICH
      # einen qdbus-Wrapper enthaelt, wird vorangestellt. Damit wird genau
      # dieser eine Befehl ueberdeckt und sonst nichts — insbesondere nicht
      # die uebrigen Qt-Werkzeuge.
      _bt_bin="${config.xdg.dataHome}/base-tooling/bin"
      if [ -x "$_bt_bin/qdbus" ]; then
        case ":$PATH:" in
          *":$_bt_bin:"*) ;;
          *) PATH="$_bt_bin:$PATH" ;;
        esac
      fi
      unset _bt_bin
      export PATH
    '';
  };

  # ── qdbus-Wrapper ───────────────────────────────────────────────────
  # Sucht zur Laufzeit die erste funktionierende qdbus-Implementierung.
  # Bewusst zur Laufzeit und nicht beim Bauen: welche Variante vorliegt,
  # unterscheidet sich zwischen Geraeten und kann sich mit einem Qt-Update
  # aendern.
  #
  # /usr/bin/qdbus steht absichtlich NICHT in der Liste — genau das ist auf
  # manchen Installationen der kaputte qtchooser-Dispatcher, den wir
  # umgehen wollen.
  xdg.dataFile."base-tooling/bin/qdbus" = {
    executable = true;
    text = ''
      #!/bin/sh
      for _c in /usr/lib/qt6/bin/qdbus /usr/bin/qdbus6 \
                /usr/lib/qt5/bin/qdbus /usr/bin/qdbus-qt6; do
        [ -x "$_c" ] && exec "$_c" "$@"
      done
      echo "qdbus: keine funktionierende Implementierung gefunden." >&2
      echo "Gesucht in /usr/lib/qt6/bin, /usr/bin/qdbus6, /usr/lib/qt5/bin." >&2
      exit 127
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
