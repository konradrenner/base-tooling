{ config, pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    dotDir = config.home.homeDirectory;

    shellAliases = {
      netbeans = ''netbeans --userdir "$(pwd)/.netbeans" > /dev/null 2>&1 &'';
    };

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

      # --- Quarkus CLI completion (zsh) ---
      if command -v quarkus >/dev/null 2>&1; then
        _q_cache_dir="''${XDG_CACHE_HOME:-$HOME/.cache}"
        mkdir -p "$_q_cache_dir"
        _q_comp_file="$_q_cache_dir/quarkus-completion.zsh"

        if [ ! -s "$_q_comp_file" ]; then
          _q_out="$(quarkus completion 2>/dev/null || true)"
          if printf '%s\n' "$_q_out" | head -n1 | grep -q '^#compdef'; then
            printf '%s\n' "$_q_out" > "$_q_comp_file"
          fi
        fi

        [ -s "$_q_comp_file" ] && source "$_q_comp_file"
        unset _q_cache_dir _q_comp_file _q_out
      fi
    '';
  };

  home.sessionVariables = {
    CLICOLOR = "1";
    LSCOLORS = "GxFxCxDxBxegedabagaced";
  };
}
