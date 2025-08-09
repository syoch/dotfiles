{ pkgs, ... }:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    syntaxHighlighting.enable = true;
    autosuggestion.enable = true;
    autocd = true;
    history = {
      save = 10000;
      size = 10000;
      share = true;
      ignoreSpace = true;
      extended = true;
      ignoreDups = true;

      ignorePatterns = [
        "ls *"
        "cd *"
        "pwd *"
        "exit *"
        "cd *"
      ];
    };
    shellAliases = {
      ls = "exa --icons --group-directories-first";
      ll = "exa --icons --long --group-directories-first";
      cat = "bat --style=plain --color=always";
      od = "hexyl --color=always";

      robotics = "asdocker ghcr.io/syoch/robotics:latest";
      retdec = "asdocker bannsec/retdec retdec-decompiler";
      asdocker = "docker run -v \$PWD:/work -w /work --rm -it";
    };
    setOptions = [
      "RM_STAR_SILENT"
      "nonomatch"
      "extended_glob"
      "no_beep"
      "nolistbeep"
    ];
    envExtra = ''
      # History searcher
      autoload history-search-end
      zle -N history-beginning-search-backward-end history-search-end
      zle -N history-beginning-search-forward-end history-search-end
      bindkey "^N" history-beginning-search-forward-end
      bindkey "^P" history-beginning-search-backward-end

      # Bash-like keybinds
      bindkey "^[[3~" delete-char
      bindkey "^A" beginning-of-line
      bindkey "^E" end-of-line
      bindkey "^[[H" beginning-of-line
      bindkey "^[[F" end-of-line

      # Completion
      zstyle ':completion:*:processes' command "ps -u $USER"

      if [ -e $HOME/.nix-profile/etc/profile.d/nix.sh ]; then
        . $HOME/.nix-profile/etc/profile.d/nix.sh
      fi

      # . "$HOME/.cargo/env"
    '';

    plugins = [
      {
        name = "powerlevel10k-config";
        src = ./.;
        file = "p10k.zsh";
      }
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];
  };
}
