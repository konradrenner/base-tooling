{ pkgs, username, ... }:

{
  # nix-darwin manages nix-daemon automatically when nix.enable = true
  nix.enable = true;

  nixpkgs.config.allowUnfree = true;

  # Primary-user Optionen (homebrew, defaults, ...)
  system.primaryUser = username;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" username ];
  };

  # Shells
  environment.shells = [ pkgs.zsh ];
  programs.zsh.enable = true;

  # Ensure user exists + correct shell (home is string ok here)
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

  system.defaults = {
    finder.AppleShowAllExtensions = true;
    NSGlobalDomain.AppleShowAllExtensions = true;
  };

  system.stateVersion = 4;

  # Fix: nixbld gid mismatch
  ids.gids.nixbld = 350;
}
