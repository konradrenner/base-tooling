# Paketlisten für die Layer, die Nix nicht verwaltet.
#
# Reine Daten, die von bootstrap.sh und sync.sh über
#   nix eval --raw .#aptInstall
# gelesen werden. Eine Quelle der Wahrheit für beide Skripte.
#
# Layer-Regeln:
#   apt     - systemnah, Kernel-/Treibernähe, KDE-Stack, Browser-Integration
#   flatpak - GUI-Apps, die von Sandbox und Portals profitieren
#   Nix     - alles andere (siehe home/common.nix)
#
# Wichtig: Die Listen müssen disjunkt sein. Ein Paket in zwei Layern
# erzeugt doppelte Einträge im Anwendungsstarter oder verschattet Binaries
# im PATH. bootstrap.sh prüft das.

{
  apt = {
    install = [
      # ── Container und Virtualisierung ─────────────────────────────
      # Docker CE aus dem offiziellen Docker-Repo: Winboat unterstützt
      # weder Podman noch rootless Container.
      "docker-ce"
      "docker-ce-cli"
      "containerd.io"
      "docker-buildx-plugin"
      "docker-compose-plugin"

      # GUI für VMs. Ersetzt VirtualBox: keine DKMS-Module, kein
      # MOK-Signieren bei Secure Boot, und teilt sich KVM konfliktfrei
      # mit Winboat.
      "virt-manager"
      "libvirt-daemon-system"
      "libvirt-clients"
      "qemu-system-x86"
      "qemu-utils"
      "bridge-utils"

      # Winboat-Voraussetzung (braucht FreeRDP 3.x)
      "freerdp3-x11"

      # ── Entwicklung ───────────────────────────────────────────────
      # VS Code aus dem MS-Repo: Flatpak plus Dev Containers plus devenv
      # ist Schmerz, und die Nix-Variante hat Integrationsprobleme.
      "code"

      # ── KDE-Stack ─────────────────────────────────────────────────
      # Kontact statt Thunderbird. KDE PIM hängt an Akonadi, kwallet und
      # Baloo — in einer Flatpak-Sandbox notorisch schmerzhaft.
      "kontact"
      "kmail"
      "korganizer"
      "kaddressbook"
      "akonadi-backend-sqlite"

      # digiKam: KDE-App auf KDE-Distro, gehört in den nativen Stack.
      "digikam"

      # LibreOffice mit KDE-Frontend: native Dateidialoge und
      # Plasma-Theming. Als Flatpak wirkt es fremd.
      "libreoffice"
      "libreoffice-kf6"
      "libreoffice-l10n-de"

      # Nextcloud-Client: die Dolphin-Integration mit Overlay-Icons
      # funktioniert aus der Sandbox nicht.
      "nextcloud-desktop"
      "dolphin-nextcloud"

      # KeePassXC: Browser-Integration läuft über Native Messaging und
      # will auf derselben Ebene wie die Browser liegen.
      "keepassxc"

      # ── Browser ───────────────────────────────────────────────────
      # Firefox liefert TuxedoOS bereits als .deb mit (kein Snap) —
      # hier nur zur Absicherung deklariert.
      "firefox"
      "google-chrome-stable"

      # ── Basis ─────────────────────────────────────────────────────
      "zsh"
      "flatpak"
      "xdg-desktop-portal-kde"
      "ca-certificates"
      "curl"
      "gnupg"
    ];

    # Wird mit `apt-get purge` entfernt.
    #
    # bootstrap.sh fährt vorher `apt-get purge --simulate` und bricht ab,
    # falls apt mehr entfernen würde als hier steht. Kein `-y` ins Blaue.
    #
    # Hinweis: Hängt eine dieser Apps an einem TUXEDO- oder
    # Kubuntu-Metapaket, entfernt das Purgen auch dessen
    # "installiert"-Markierung. Ein grosses Distro-Upgrade kann das Bundle
    # dann erneut einziehen — der nächste sync.sh purged es wieder.
    purge = [
      # Kontact übernimmt. TuxedoOS liefert Thunderbird als .deb aus,
      # nicht als Snap, deshalb greift apt hier.
      "thunderbird"

      # Von TuxedoOS mitgeliefert, nicht benötigt
      "mc"
      "ktorrent"
      "elisa"
      "zutty"

      # KDE-Spiele
      "kmahjongg"
      "kmines"
      "kpatience"
      "ksudoku"

      # Global nicht benötigt. Für Ad-hoc-Bildbearbeitung gibt devenv es
      # projektweise aus Nix.
      # Achtung: Das Paket hat Bibliotheken drumherum — der
      # --simulate-Check von bootstrap.sh ist hier besonders relevant.
      "imagemagick"
    ];
  };

  flatpak = {
    # Reihenfolge ist relevant: nix-flatpak installiert der Liste nach und
    # bricht beim ersten Fehler ab. Ein problematisches Paket vorne verhindert
    # damit die Installation aller folgenden.
    packages = [
      "org.gimp.GIMP"
      "org.videolan.VLC"
      "org.inkscape.Inkscape"
      # Auf Ubuntu-Basis der bessere Weg als apt: keine
      # 32-Bit-Multiarch-Kaskade.
      "com.valvesoftware.Steam"

      # ACHTUNG, schlaegt auf Ubuntu-Basis derzeit fehl.
      #
      # Spotifys Flatpak ist ein extra-data-Paket: es laedt bei der
      # Installation den echten Spotify-Client nach und fuehrt dessen
      # apply_extra-Skript in bwrap mit eigenem Netzwerk-Namespace aus.
      # Ubuntu 24.04+ setzt kernel.apparmor_restrict_unprivileged_userns=1,
      # womit bwrap das Loopback-Interface nicht aufsetzen darf:
      #   bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted
      #   Error: apply_extra ist fehlgeschlagen, Exit-Status 256
      #
      # Deshalb bewusst ans Ende der Liste gestellt: so installieren sich die
      # vier Pakete darueber, bevor der Service abbricht.
      #
      # Zwei Auswege, beide noch nicht entschieden:
      #   a) Spotify aus apt beziehen (offizielles Repo, native .deb) und hier
      #      streichen — loest das Sandbox-Problem, statt es zu umgehen
      #   b) die AppArmor-Einschraenkung lockern:
      #      sysctl kernel.apparmor_restrict_unprivileged_userns=0
      #      schwaecht allerdings eine systemweite Absicherung fuer eine App
      "com.spotify.Client"
    ];
  };
}
