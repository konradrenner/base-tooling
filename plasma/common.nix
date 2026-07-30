{ config, pkgs, lib, ... }:

# Portable Plasma-Basis, destilliert aus dem rc2nix-Export.
#
# Bewusst NICHT übernommen:
#   * khotkeysrc komplett  - die KDE-Beispielgesten, alle deaktiviert und mit
#                            fehlerhaft kodierten Umlauten. KDE legt die
#                            Defaults selbst wieder an.
#   * dataFile / Kate-Sessions - enthielten offene Dateien aus ~/Downloads
#   * Kate-Such- und Ersetzungshistorie - enthielt Projekt- und Servicenamen
#   * katefilebrowser location - absoluter Projektpfad
#   * spectaclerc Speicherpfade, plasmarc usersWallpapers - private Fotopfade
#   * plasmanotifyrc "Seen"-Flags, dolphinrc ViewPropsTimestamp,
#     dolphinrc ExtractDialog-Fenstergrößen - reiner Laufzeitzustand
#   * amarok-Shortcuts (nicht installiert), wacomtablet (kein Tablet),
#     Baloo-Exclude-Filter (KDE-Default)
#   * ktrashrc - enthielt einen hartkodierten Home-Pfad
#
# Maschinenspezifisches liegt in plasma/notebook.nix bzw. plasma/desktop.nix.

{
  # ── Konsole ─────────────────────────────────────────────────────────
  # Übersetzung einer Ghostty-Config. Jede Zeile ist mit ihrer
  # Ghostty-Entsprechung kommentiert, damit nachvollziehbar bleibt,
  # woher der Wert kommt.
  #
  # Achtung: programs.konsole ist eine Top-Level-Option von plasma-manager,
  # NICHT unter programs.plasma verschachtelt.
  #
  # Nicht übertragbar und laut Absprache nicht benötigt:
  #   keybind = alt+s>...       - Konsole kennt nur Einzelakkorde,
  #                               keine Mehrtasten-Sequenzen
  #   shell-integration         - kein Konsole-Äquivalent; das Problem, das
  #                               es bei Ghostty löst (TERM=xterm-ghostty
  #                               fehlt in terminfo), entsteht hier nicht,
  #                               weil Konsole sich als xterm-256color meldet
  #   selection-background/-foreground - Konsole-Farbschemata dokumentieren
  #                               keine eigenen Selection-Farben; Dracula
  #                               regelt das selbst
  #   mouse-hide-while-typing   - kein bekanntes Konsole-Äquivalent
  programs.konsole = {
    enable = true;
    defaultProfile = "base-tooling";

    customColorSchemes = {
      # theme = Dracula, inkl. background-opacity = 0.6
      Dracula = ./dracula.colorscheme;
    };

    profiles.base-tooling = {
      name = "base-tooling";
      colorScheme = "Dracula";

      # font-family / font-size
      font = {
        name = "JetBrainsMono Nerd Font Mono";
        size = 14;
      };

      extraConfig = {
        General = {
          # working-directory = ~/code
          Directory = "$HOME/code";
          StartInCurrentSessionDir = "false";
          # window-width = 110 / window-height = 32
          TerminalColumns = "110";
          TerminalRows = "32";
        };

        Appearance = {
          # adjust-cell-height = 10% -> Konsole rechnet in Pixeln,
          # 2px sind bei Schriftgröße 14 die nächstliegende Annäherung.
          LineSpacing = "2";
        };

        "Cursor Options" = {
          # cursor-style = bar  (0=Block, 1=IBeam, 2=Underline)
          CursorShape = "1";
        };

        "Interaction Options" = {
          # copy-on-select = clipboard
          AutoCopySelectedText = "true";
          TrimTrailingSpacesInSelectedText = "true";
        };

        Scrolling = {
          # Unbegrenzter Scrollback
          HistoryMode = "2";
        };
      };
    };
  };

  programs.plasma = {
    enable = true;

    # false = deklarativer Boden, manuelle Änderungen in den Systemeinstellungen
    # bleiben erhalten. Auf true würde jeder switch alles Nicht-Deklarierte
    # auf Default zurücksetzen.
    overrideConfig = false;

    # ── Shortcuts ─────────────────────────────────────────────────────
    shortcuts = {
      # Fensterverwaltung
      kwin."Edit Tiles" = "Meta+T";
      kwin."Grid View" = "Meta+G";
      kwin.Overview = "Meta+W";
      kwin."Show Desktop" = "Meta+D";
      kwin."Window Maximize" = "Meta+PgUp";
      kwin."Window Minimize" = "Meta+PgDown";
      kwin."Window Close" = "Alt+F4";
      kwin."Window Operations Menu" = "Alt+F3";
      kwin."Kill Window" = "Ctrl+Alt+Esc";
      kwin."Suspend Compositing" = "Alt+Shift+F12";
      kwin.disableInputCapture = "Meta+Shift+Esc";
      kwin."Activate Window Demanding Attention" = "Ctrl+Alt+A";

      # Fenster wechseln
      kwin."Switch Window Down" = "Meta+Alt+Down";
      kwin."Switch Window Left" = "Meta+Alt+Left";
      kwin."Switch Window Right" = "Meta+Alt+Right";
      kwin."Switch Window Up" = "Meta+Alt+Up";
      kwin."Walk Through Windows" = "Alt+Tab";
      kwin."Walk Through Windows (Reverse)" = "Alt+Shift+Backtab";
      kwin."Walk Through Windows of Current Application" = "Alt+`";
      kwin."Walk Through Windows of Current Application (Reverse)" = "Alt+~";

      # Kacheln
      kwin."Window Quick Tile Bottom" = "Meta+Down";
      kwin."Window Quick Tile Left" = "Meta+Left";
      kwin."Window Quick Tile Right" = "Meta+Right";
      kwin."Window Quick Tile Top" = "Meta+Up";

      # Virtuelle Desktops
      kwin."Switch to Desktop 1" = [ "Ctrl+F1" "Meta+F1" ];
      kwin."Switch to Desktop 2" = [ "Ctrl+F2" "Meta+F2" ];
      kwin."Switch to Desktop 3" = [ "Meta+F3" "Ctrl+F3" ];
      kwin."Switch to Desktop 4" = [ "Ctrl+F4" "Meta+F4" ];
      kwin."Window One Desktop Down" = "Meta+Ctrl+Shift+Down";
      kwin."Window One Desktop Up" = "Meta+Ctrl+Shift+Up";
      kwin."Window One Desktop to the Left" = "Meta+Ctrl+Shift+Left";
      kwin."Window One Desktop to the Right" = "Meta+Ctrl+Shift+Right";

      # Mehrere Bildschirme
      kwin."Window to Next Screen" = "Meta+Shift+Right";
      kwin."Window to Previous Screen" = "Meta+Shift+Left";

      # Zoom und Mauszeiger
      kwin.view_actual_size = "Meta+0";
      kwin.view_zoom_in = "Meta+=";
      kwin.view_zoom_out = "Meta+-";
      kwin.MoveMouseToCenter = "Meta+F6";
      kwin.MoveMouseToFocus = "Meta+F5";

      # Fenster-Übersichten
      kwin.Expose = "Ctrl+F9";
      kwin.ExposeAll = [ "Ctrl+F10" "Launch (C)" ];
      kwin.ExposeClass = "Ctrl+F7";

      # Session
      ksmserver."Lock Session" = [ "Meta+L" "Ctrl+Alt+L" "Screensaver" ];
      ksmserver."Log Out" = "Ctrl+Alt+Del";

      # Plasma-Shell
      plasmashell."activate application launcher" = "Meta";
      plasmashell."activate task manager entry 1" = "Meta+1";
      plasmashell."activate task manager entry 2" = "Meta+2";
      plasmashell."activate task manager entry 3" = "Meta+3";
      plasmashell."activate task manager entry 4" = "Meta+4";
      plasmashell."activate task manager entry 5" = "Meta+5";
      plasmashell."activate task manager entry 6" = "Meta+6";
      plasmashell."activate task manager entry 7" = "Meta+7";
      plasmashell."activate task manager entry 8" = "Meta+8";
      plasmashell."activate task manager entry 9" = "Meta+9";
      plasmashell.clipboard_action = "Ctrl+Alt+X";
      plasmashell.show-on-mouse-pos = "Meta+V";
      plasmashell.cycle-panels = "Meta+Alt+P";
      plasmashell."manage activities" = "Meta+Q";
      plasmashell."previous activity" = "Meta+Shift+A";
      plasmashell.repeat_action = "Ctrl+Alt+R";
      plasmashell."show dashboard" = "Ctrl+F12";

      # Barrierefreiheit und Energie
      kaccess."Toggle Screen Reader On and Off" = "Meta+Alt+S";
      org_kde_powerdevil.powerProfile = [ "Battery" "Meta+B" ];

      # Tastaturlayout
      "KDE Keyboard Layout Switcher"."Switch to Next Keyboard Layout" = "Ctrl+Alt+K";
      "KDE Keyboard Layout Switcher"."Switch to Last-Used Keyboard Layout" = "Meta+Alt+L";
    };

    # ── Panel ─────────────────────────────────────────────────────────
    # Nachgebaut aus dem appletsrc: Containment 2, location=5 (links),
    # formfactor=3 (vertikal), AppletOrder=46;37;36;5;6;7;20.
    #
    # ACHTUNG, zwei Nebenwirkungen beim ersten Anwenden:
    #
    # 1. plasma-manager löscht vorher plasma-org.kde.plasma.desktop-appletsrc
    #    komplett und baut sie neu. In derselben Datei stecken auch die
    #    Desktop-Containments — die Analoguhr und das TUXEDO Control Hub auf
    #    dem Desktop sowie die Ordneransichten gehen dabei verloren und
    #    müssen einmal von Hand wieder angelegt werden. Wer sie deklarieren
    #    will, braucht programs.plasma.desktop.widgets samt Position und
    #    Größe jedes Widgets.
    #
    # 2. height = 44 ist Plasmas Standarddicke. Im appletsrc gab es keine
    #    [PlasmaViews]-Sektion, das Panel lief also auf dem Default — nach
    #    dem Anwenden bitte kurz vergleichen.
    #
    # Vorher testen, nicht direkt auf dem Arbeitsgerät: das desktop-Profil in
    # einer VM anwenden, Ergebnis ansehen, dann erst auf dem Notebook.
    panels = [
      {
        location = "left";
        height = 44;

        widgets = [
          "org.kde.plasma.kickoff"
          "org.kde.plasma.pager"
          "org.kde.plasma.notes"

          {
            iconTasks = {
              # Angepinnte Anwendungen, Reihenfolge wie gehabt.
            #
            # Zwei Einträge weichen bewusst vom aktuellen appletsrc ab:
            # VLC und GIMP kommen in diesem Setup aus Flatpak, nicht aus apt.
            # Ihre Desktop-Dateien heissen deshalb org.videolan.VLC.desktop
            # und org.gimp.GIMP.desktop statt vlc.desktop und gimp.desktop —
            # mit den alten Namen wären die beiden Pins nach einer
            # Neuinstallation ins Leere zeigend.
              launchers = [
                "applications:libreoffice-startcenter.desktop"
                "preferred://filemanager"
                "applications:org.kde.konsole.desktop"
                "applications:firefox.desktop"
                "applications:org.kde.kontact.desktop"
                "applications:org.videolan.VLC.desktop"
                "applications:org.gimp.GIMP.desktop"
              ];
            };
          }

          "org.kde.plasma.marginsseparator"
          "org.kde.plasma.systemtray"
          "org.kde.plasma.digitalclock"
        ];
      }
    ];

    # ── Globales Thema ────────────────────────────────────────────────
    # Musste hier von Hand ergänzt werden: rc2nix sperrt die Schlüssel
    # LookAndFeelPackage, ColorScheme und alles, was auf "Theme" endet
    # (KEY_BLOCK_LIST). Im Export war davon also nichts enthalten.
    #
    # Das Look-and-Feel-Paket bringt Farbschema, Plasma-Stil, Icons,
    # Cursor und Fensterdekoration in einem mit — deshalb wird hier nur
    # dieser eine Wert gesetzt statt fünf einzelne, die auseinanderdriften
    # könnten.
    #
    # Angewandt wird es mit `plasma-apply-lookandfeel -a`, bewusst OHNE
    # --resetLayout. Das Panel-Layout bleibt damit unangetastet.
    workspace = {
      lookAndFeel = "org.kde.breezedark.desktop";

      # Nur setzen, wenn du bewusst von den Vorgaben des Themas abweichst.
      # Gültige Werte findest du mit:
      #   plasma-apply-colorscheme --list-schemes
      #   plasma-apply-desktoptheme --list-themes
      #   plasma-apply-cursortheme --list-themes
      # colorScheme = "BreezeDark";
      # theme = "breeze-dark";
      # iconTheme = "breeze-dark";
      # cursor = { theme = "breeze_cursors"; size = 24; };
    };

    # ── Web-Shortcuts ─────────────────────────────────────────────────
    # plasma-manager verwaltet kuriikwsfilterrc über ein eigenes Modul,
    # deshalb hier die Option statt der rohen rc-Schlüssel.
    searchPlugins.webSearchKeywords = {
      enable = true;
      delimiter = ":";
      preferred = [ "youtube" "google" "wikit" "wikipedia" "github" "yahoo" ];
      usePreferredOnly = false;
    };

    # ── configFile ────────────────────────────────────────────────────
    configFile = {
      # Dateisuche
      baloofilerc."Basic Settings".Indexing-Enabled = true;

      # Dolphin
      dolphinrc.IconsMode.PreviewSize = 128;
      dolphinrc."KFileDialog Settings"."Places Icons Auto-resize" = false;
      dolphinrc."KFileDialog Settings"."Places Icons Static Size" = 22;

      # Kate: Editor-Verhalten und Schrift
      katerc.General."Show Menu Bar" = true;
      katerc.General."Show Status Bar" = true;
      katerc.General."Show Tab Bar" = true;
      katerc.General."Show Url Nav Bar" = true;
      katerc.General."Show Full Path in Title" = false;
      katerc."KTextEditor Document"."Auto Detect Indent" = true;
      katerc."KTextEditor Document"."Auto Reload If State Is In Version Control" = true;
      katerc."KTextEditor Document"."Camel Cursor" = true;
      katerc."KTextEditor Document".Encoding = "UTF-8";
      katerc."KTextEditor Document"."Indentation Width" = 4;
      katerc."KTextEditor Document"."Newline at End of File" = true;
      katerc."KTextEditor Document".ReplaceTabsDyn = true;
      katerc."KTextEditor Document"."Show Tabs" = true;
      katerc."KTextEditor Document"."Smart Home" = true;
      katerc."KTextEditor Document"."Tab Width" = 4;
      katerc."KTextEditor Renderer"."Color Theme" = "Breeze Light";
      katerc."KTextEditor Renderer"."Auto Color Theme Selection" = true;
      katerc."KTextEditor Renderer".Font = "Hack,10,-1,7,50,0,0,0,0,0";
      katerc."KTextEditor Renderer"."Text Font" = "Hack,10,-1,7,400,0,0,0,0,0,0,0,0,0,0,1";
      katerc."KTextEditor View"."Auto Completion" = true;
      katerc."KTextEditor View"."Dynamic Word Wrap" = true;
      katerc."KTextEditor View"."Folding Bar" = true;
      katerc."KTextEditor View"."Folding Preview" = true;
      katerc."KTextEditor View"."Line Numbers" = true;
      katerc."KTextEditor View"."Line Modification" = true;
      katerc."KTextEditor View"."Scroll Bar MiniMap" = true;
      katerc."KTextEditor View"."Scroll Bar Mini Map All" = true;
      katerc."KTextEditor View"."Scroll Bar Mini Map Width" = 60;
      katerc."KTextEditor View"."Scroll Bar Preview" = true;
      katerc."KTextEditor View"."Show File Encoding" = true;
      katerc."KTextEditor View"."Show Statusbar Line Column" = true;
      katerc."KTextEditor View"."Word Completion" = true;

      # KDE-Grundverhalten
      kdeglobals.General.XftSubPixel = "none";
      kdeglobals.KDE.SingleClick = true;
      kdeglobals.KDE.ScrollbarLeftClickNavigatesByPage = false;
      kdeglobals.PreviewSettings.EnableRemoteFolderThumbnail = false;
      kdeglobals.PreviewSettings.MaximumRemoteSize = 10485760;

      # Dunkle Titelleisten
      kdeglobals.WM.activeBackground = "39,44,49";
      kdeglobals.WM.activeBlend = "252,252,252";
      kdeglobals.WM.activeForeground = "252,252,252";
      kdeglobals.WM.inactiveBackground = "32,36,40";
      kdeglobals.WM.inactiveBlend = "161,169,177";
      kdeglobals.WM.inactiveForeground = "161,169,177";

      # Dateidialoge
      kdeglobals."KFileDialog Settings"."Sort directories first" = true;
      kdeglobals."KFileDialog Settings"."Show Speedbar" = true;
      kdeglobals."KFileDialog Settings"."Show Inline Previews" = true;
      kdeglobals."KFileDialog Settings"."Show hidden files" = false;
      kdeglobals."KFileDialog Settings"."View Style" = "Simple";
      kdeglobals."KFileDialog Settings"."Automatically select filename extension" = true;

      # Nervige Dienste abschalten
      kded5rc.Module-browserintegrationreminder.autoload = false;
      kded5rc.Module-device_automounter.autoload = false;

      # Bestätigungen und Skriptverhalten
      kiorc.Confirmations.ConfirmDelete = true;
      kiorc.Confirmations.ConfirmEmptyTrash = true;
      kiorc.Confirmations.ConfirmTrash = false;
      kiorc."Executable scripts".behaviourOnLaunch = "execute";

      # KRunner
      krunnerrc.General.historyBehavior = "ImmediateCompletion";
      krunnerrc.Plugins.baloosearchEnabled = true;

      # Sperrbildschirm (Kulanzzeit in Sekunden)
      kscreenlockerrc.Daemon.LockGrace = 35;

      # Wallet: nur Verhalten, keine Geheimnisse
      kwalletrc.Wallet.Enabled = true;
      kwalletrc.Wallet."Close When Idle" = false;
      kwalletrc.Wallet."Close on Screensaver" = false;
      kwalletrc.Wallet."Default Wallet" = "kdewallet";
      kwalletrc.Wallet."First Use" = false;
      kwalletrc.Wallet."Leave Open" = true;
      kwalletrc.Wallet."Prompt on Open" = false;
      kwalletrc.Wallet."Use One Wallet" = true;
      kwalletrc."org.freedesktop.secrets".apiEnabled = false;

      # KWin
      kwinrc.Desktops.Number = 4;
      kwinrc.Desktops.Rows = 2;
      kwinrc.ElectricBorders.TopLeft = "ShowDesktop";
      kwinrc.Effect-overview.BorderActivate = 9;
      kwinrc.MouseBindings.CommandActiveTitlebar2 = "Operations menu";
      kwinrc.MouseBindings.CommandAllWheel = "Change Opacity";
      kwinrc.NightColor.Active = true;
      kwinrc.Plugins.shakecursorEnabled = true;
      kwinrc.Tiling.padding = 4;
      kwinrc.Compositing.OpenGLIsUnsafe = false;
      kwinrc."org.kde.kdecoration2".ButtonsOnLeft = "XAIL";
      kwinrc."org.kde.kdecoration2".ButtonsOnRight = "SM";

      # Maus (geräteunabhängig; das Touchpad steht im Host-Modul)
      kcminputrc.Mouse.X11LibInputXAccelProfileFlat = false;

      # Sprache und Formate
      plasma-localerc.Formats.LANG = "de_AT.UTF-8";

      # Spectacle: nur Präferenzen, keine Pfade
      spectaclerc.Annotations.annotationToolType = 1;
      spectaclerc.GuiConfig.captureMode = 0;
    };
  };
}
