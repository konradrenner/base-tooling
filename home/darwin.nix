{ config, pkgs, lib, ... }:

{

  programs.vscode = {
    enable = true;

    profiles.default = {
      userSettings = {
        "workbench.startupEditor" = "none";
        "update.showReleaseNotes" = false;
      };
    };

    profiles.default.extensions = pkgs.nix4vscode.forVscode [
      "ms-vscode-remote.remote-containers"
      "asciidoctor.asciidoctor-vscode"
      "jebbs.plantuml"
      "alphabotsec.vscode-eclipse-keybindings"
      "OleksandrHavrysh.intellij-formatter"
      "jnoortheen.nix-ide"
      "anthropic.claude-code"
    ];
  };

  # macOS-Aliases in ~/Applications erstellen, damit Spotlight VS Code findet
  home.packages = with pkgs; [ mkalias ];

  home.activation.linkApps = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    apps_dir="$HOME/Applications/Home Manager Apps"
    $DRY_RUN_CMD rm -rf "$apps_dir"
    $DRY_RUN_CMD mkdir -p "$apps_dir"
    for app in "$HOME"/.nix-profile/Applications/*.app; do
      [ -e "$app" ] || continue
      real="$(readlink -f "$app")"
      $DRY_RUN_CMD ${pkgs.mkalias}/bin/mkalias "$real" "$apps_dir/$(basename "$app")"
    done
  '';

  programs.zsh.shellAliases = {
    netbeans = ''netbeans --userdir "$(pwd)/.netbeans" > /dev/null 2>&1 &'';
  };

  home.sessionVariables = {
    CLICOLOR = "1";
    LSCOLORS = "GxFxCxDxBxegedabagaced";
  };
}
