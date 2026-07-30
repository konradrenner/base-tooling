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

      # Winboat-Voraussetzungen. Das .deb deklariert sie laut Projektdoku
      # nicht selbst, deshalb hier explizit.
      # ACHTUNG: freerdp3-x11 ist ein ungepruefter Paketname.
      "freerdp3-x11"
      "usbutils"

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

      # ── Multimedia ────────────────────────────────────────────────
      # Nativ statt Flatpak, weil Spotifys Flatpak als extra-data-Paket an
      # Ubuntus Einschraenkung unprivilegierter User-Namespaces scheitert.
      # Begruendung ausfuehrlich in system/repos.nix.
      "spotify-client"

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

  # ── Einzelne .deb-Releases ──────────────────────────────────────────
  # Fuer Programme, die es weder in einem apt-Repo noch auf Flathub gibt.
  # URL und sha256 sind gepinnt, das Setup ist damit reproduzierbar, ohne
  # dass etwas aus dem Netz ungeprueft installiert wird.
  #
  # Beim Aktualisieren: neue Version eintragen und den Hash neu bestimmen mit
  #   curl -sL <url> | sha256sum
  debs = [
    {
      name = "winboat";
      version = "0.9.0";
      url = "https://github.com/TibixDev/winboat/releases/download/v0.9.0/winboat-0.9.0-amd64.deb";
      sha256 = "91d4d10d173fb572fba7c30ad49a2397374e4cde1bc5b4f807573890962afe4e";
      # Bewusst NICHT aus nixpkgs, obwohl es dort liegt: Winboats
      # Guest-Server ist in Go geschrieben und wird fuer Windows
      # cross-kompiliert. Da winboat im Binary-Cache fehlt, baut das den
      # Go-Compiler und die MinGW-Toolchain lokal und zieht 1,4 GiB
      # Electron-Abhaengigkeiten nach. Zudem verlangt die nixpkgs-Variante
      # eine Freigabe fuer das als unsicher markierte Electron 40.
      #
      # Das Upstream-.deb buendelt dieselbe Electron-Version und denselben
      # Guest-Server, nur fertig gebaut — also genau das, was das Projekt
      # auch testet.
    }
  ];

  flatpak = {
    # Reihenfolge ist relevant: nix-flatpak installiert der Liste nach und
    # bricht beim ersten Fehler ab. Ein problematisches Paket vorne verhindert
    # damit die Installation aller folgenden. Kandidaten dafuer sind vor allem
    # extra-data-Pakete, die bei der Installation Inhalte nachladen und in
    # bwrap auspacken.
    #
    # Spotify stand hier und ist bewusst nach apt gewandert, siehe
    # system/repos.nix.
    packages = [
      "org.gimp.GIMP"
      "org.videolan.VLC"
      "org.inkscape.Inkscape"
      # Auf Ubuntu-Basis der bessere Weg als apt: keine
      # 32-Bit-Multiarch-Kaskade.
      "com.valvesoftware.Steam"
    ];
  };
}
