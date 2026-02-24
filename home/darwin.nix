{ config, pkgs, ... }:

{
  # macOS-specific Home Manager configuration

  # Use zsh on macOS (Linux stays on bash)
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    # A few sensible defaults
    initExtra = ''
      setopt HIST_IGNORE_ALL_DUPS
      setopt HIST_REDUCE_BLANKS
      export EDITOR=${EDITOR:-code}
    '';
  };

  # Ensure direnv hook is enabled for zsh
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # Optional: basic XDG defaults (safe baseline)
  xdg.enable = true;
}
