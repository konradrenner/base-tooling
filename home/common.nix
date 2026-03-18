{ config, pkgs, lib, username, ... }:

let
  homeDir =
    if pkgs.stdenv.isDarwin
    then /. + "/Users/${username}"
    else /. + "/home/${username}";

  gitName =
    let n = builtins.getEnv "BASE_TOOLING_GIT_NAME";
    in if n != "" then n else throw ''
      BASE_TOOLING_GIT_NAME is not set.

      Use install/update scripts with: --git-name "Your Name"
      Or run nix with: BASE_TOOLING_GIT_NAME="Your Name" ... --impure
    '';

  gitEmail =
    let e = builtins.getEnv "BASE_TOOLING_GIT_EMAIL";
    in if e != "" then e else throw ''
      BASE_TOOLING_GIT_EMAIL is not set.

      Use install/update scripts with: --git-email "you@example.com"
      Or run nix with: BASE_TOOLING_GIT_EMAIL="you@example.com" ... --impure
    '';
in
{
  xdg.enable = true;
  home.username = lib.mkForce username;
  home.homeDirectory = lib.mkForce homeDir;

  home.stateVersion = "24.11";

  programs.git = {
    enable = true;
    userName = gitName;
    userEmail = gitEmail;
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    initContent = ''
      autoload -Uz vcs_info
      precmd() { vcs_info }

      zstyle ':vcs_info:git:*' formats ' (%b%u%c)'
      zstyle ':vcs_info:git:*' actionformats ' (%b|%a%u%c)'
      zstyle ':vcs_info:git:*' stagedstr '+'
      zstyle ':vcs_info:git:*' unstagedstr '*'
      zstyle ':vcs_info:git:*' check-for-changes true

      setopt PROMPT_SUBST
      PROMPT='%F{green}%n@%m%f:%F{blue}%~%f%F{yellow}$vcs_info_msg_0_%f%(!.#.$) '

      # ---- Quarkus CLI completion ----
      if command -v quarkus >/dev/null 2>&1; then
        autoload -Uz bashcompinit
        bashcompinit

        # Quarkus completion sometimes emits extra output -> keep it quiet
        source <(quarkus completion 2>/dev/null)
      fi
    '';
  };

  home.packages = with pkgs; [
    netbeans
    curl
    jq
    git
    gh
    devenv
    graphviz
    plantuml
    fontconfig
    graalvmPackages.graalvm-ce
    quarkus
    jbang
  ];
}
