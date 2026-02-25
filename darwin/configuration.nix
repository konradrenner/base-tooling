{ pkgs, lib, username, ... }:

{
  # nix-darwin now manages the nix-daemon automatically when nix.enable = true
  nix.enable = true;

  nixpkgs.config.allowUnfree = true;

  # Required for a bunch of "primary-user" options (homebrew, defaults, etc.)
  system.primaryUser = username;

  # Recommended Nix settings for flakes
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" username ];
  };

  # Shells
  environment.shells = [ pkgs.zsh ];
  programs.zsh.enable = true;

  # Ensure the user exists + has the right shell (home is a string here, that's fine)
  users.users.${username} = {
    home = "/Users/${username}";
    shell = pkgs.zsh;
  };

  # Homebrew (declarative)
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "zap";
    };

    casks = [
      "rancher"
    ];
  };

  # macOS defaults
  system.defaults = {
    finder.AppleShowAllExtensions = true;
    NSGlobalDomain.AppleShowAllExtensions = true;
  };

  # nix-darwin state tracking
  system.stateVersion = 4;

  ids.gids.nixbld = 350;
}
