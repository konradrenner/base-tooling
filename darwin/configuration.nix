{ pkgs, ... }:

{
  # ------------------------------------
  # nix-darwin system configuration
  # ------------------------------------

  # Enable nix-daemon (required for multi-user Nix on macOS)
  services.nix-daemon.enable = true;

  # Allow unfree packages (VS Code etc.)
  nixpkgs.config.allowUnfree = true;

  # ------------------------------------
  # Homebrew (managed declaratively)
  # ------------------------------------
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "zap";
    };

    # Rancher Desktop (Option A container engine)
    casks = [
      "rancher"
    ];
  };

  # ------------------------------------
  # Shell configuration
  # ------------------------------------

  # Make zsh available as a system shell
  environment.shells = [ pkgs.zsh ];

  # Set default shell for user
  users.users.konrad = {
    shell = pkgs.zsh;
  };

  # ------------------------------------
  # macOS system defaults (sane baseline)
  # ------------------------------------
  system.defaults = {
    dock.autohide = true;
    finder.AppleShowAllExtensions = true;
    NSGlobalDomain.AppleShowAllExtensions = true;
  };

  # Required for nix-darwin state tracking
  system.stateVersion = 4;
}
