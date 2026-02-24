{ pkgs, username, ... }:

{
  # -----------------------------
  # nix-darwin system config
  # -----------------------------

  # Multi-user Nix on macOS
  services.nix-daemon.enable = true;

  # Allow unfree packages (e.g. VS Code)
  nixpkgs.config.allowUnfree = true;

  # -----------------------------
  # Homebrew (declarative)
  # -----------------------------
  # Note: Homebrew must exist. install.sh ensures it on Day-0.
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "zap";
    };

    # Rancher Desktop (Dev Containers engine option)
    casks = [
      "rancher"
    ];
  };

  # -----------------------------
  # Shells / user
  # -----------------------------
  environment.shells = [ pkgs.zsh ];

  users.users.${username} = {
    shell = pkgs.zsh;
  };

  # -----------------------------
  # macOS defaults (safe baseline)
  # -----------------------------
  system.defaults = {
    dock.autohide = true;
    finder.AppleShowAllExtensions = true;
    NSGlobalDomain.AppleShowAllExtensions = true;
  };

  # Required for nix-darwin state tracking
  system.stateVersion = 4;
}
