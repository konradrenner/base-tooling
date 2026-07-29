{ config, pkgs, lib, username, homeDirectory, ... }:

{
  home.username = username;
  home.homeDirectory = homeDirectory;

  # Konservativ gehalten: eine ältere stateVersion behält ältere Defaults bei
  # und ist immer gültig. Erhöhen erst nach Blick in die Home-Manager-Release-Notes.
  home.stateVersion = "24.11";

  xdg.enable = true;

  # Nötig, damit fontconfig auf einer Fremddistro die Nix-Fonts findet
  # (z.B. die Nerd Font für Powerlevel10k und `eza --icons`).
  fonts.fontconfig.enable = true;

  # ── Pakete ──────────────────────────────────────────────────────────
  # Hier landet ausschliesslich Nicht-GUI- und Toolchain-Zeug.
  # GUI-Apps kommen aus Flatpak, Systemnahes aus apt (system/packages.nix).
  #
  # Bewusst NICHT hier: docker, docker-compose, freerdp, libreoffice, vlc,
  # gimp, vscode. Die kommen aus apt bzw. Flatpak; eine Nix-Variante würde
  # den apt-Client im PATH überschatten oder die Desktop-Integration brechen.
  home.packages = with pkgs; [
    # Java-Toolchain
    curl
    jq
    graalvmPackages.graalvm-ce
    jbang
    maven
    quarkus

    # Allgemeines Werkzeug
    git
    gh
    devenv
    graphviz
    plantuml

    # Shell-UX
    eza
    fzf

    # IDE (Swing, deshalb unkritisch aus Nix)
    netbeans

    # Genealogie: kein Flathub, kein nixpkgs -> eigene AppImage-Derivation.
    # Bewusst deaktiviert, bis der Hash in pkgs/ancestris.nix eingetragen ist —
    # sonst würde ein Platzhalter-Hash jeden `switch` scheitern lassen.
    # Vorgehen: `nix build .#ancestris` ausführen, den genannten Hash
    # eintragen, dann diese Zeile einkommentieren.
    # (pkgs.callPackage ../pkgs/ancestris.nix { })

    # Font für p10k-Prompt und eza-Icons
    nerd-fonts.jetbrains-mono
  ];

  # ── Git ─────────────────────────────────────────────────────────────
  programs.git = {
    enable = true;
    # Email absichtlich nicht global: pro Repo setzen mit
    #   git config --local user.email "you@example.com"
    settings = {
      init.defaultBranch = "main";
      pull.ff = "only";
    };
  };

  # ── direnv ──────────────────────────────────────────────────────────
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # ── fzf ─────────────────────────────────────────────────────────────
  # Liefert die `fzf --zsh`-Integration.
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  # ── zsh ─────────────────────────────────────────────────────────────
  # Prompt: Powerlevel10k. Ergänzt um fzf-tab, Autosuggestions und
  # Syntax-Highlighting. Tastenkombinationen werden bewusst nicht gesetzt.
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autocd = true;

    # Ab Home Manager 26.05 wechselt der Default auf $XDG_CONFIG_HOME/zsh.
    # Hier bewusst festgenagelt auf ~/.zshrc — das ist der Ort, an dem man
    # die Datei erwartet, und passt zur Login-Shell-Einrichtung.
    dotDir = config.home.homeDirectory;

    autosuggestion = {
      enable = true;
      strategy = [ "history" ];
    };

    syntaxHighlighting.enable = true;

    history = {
      size = 10000;
      save = 10000;
      share = true;
      append = true;
      extended = false;
      ignoreDups = true;
      ignoreAllDups = true;
      ignoreSpace = true;
      expireDuplicatesFirst = true;
      findNoDups = false;
      saveNoDups = false;
    };

    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "sudo" "docker" ];
    };

    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
      {
        name = "fzf-tab";
        src = pkgs.zsh-fzf-tab;
        file = "share/fzf-tab/fzf-tab.plugin.zsh";
      }
    ];

    shellAliases = {
      # eza als ls-Ersatz
      ls = "eza --icons=always --git --classify --show-symlinks --group-directories-first -m";
      ll = "ls --long --header --all --sort modified";
      la = "ll";
      dir = "ll";
      # Neu auf Wunsch: direktes Äquivalent zu `ls -la`,
      # ohne Header und ohne Sortierung nach Änderungsdatum.
      lsa = "ls --long --all";
    };

    initContent = ''
      # Von Home Manager nicht als Option abgedeckt
      setopt HIST_FCNTL_LOCK

      # Prompt-Aussehen: Ausgabe von `p10k configure`, unverändert
      # eingecheckt in home/p10k.zsh.
      [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
    '';
  };

  home.file.".p10k.zsh".source = ./p10k.zsh;
}
