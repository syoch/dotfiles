{
  pkgs,
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.hm-module.zsh;
in
{
  options.hm-module.zsh = {
    enable = mkEnableOption "zsh";
  };

  config = mkIf cfg.enable {
    programs.bat.enable = true;
    programs.eza.enable = true;
    programs.eza.enableZshIntegration = true;

    programs.zsh = {
      enable = true;
      enableCompletion = true;
      syntaxHighlighting.enable = true;
      autosuggestion.enable = true;
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
        ls = "eza --icons --group-directories-first";
        ll = "eza --icons --long --group-directories-first";
        cat = "bat --style=plain --color=always";

        hexyl = "${pkgs.hexyl}/bin/hexyl --color=always";
        od = "hexyl";

        asdocker = "docker run -v \$PWD:/work -w /work --rm -it";
        robotics = "asdocker ghcr.io/syoch/robotics:latest";
        retdec = "asdocker bannsec/retdec retdec-decompiler";
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
  };
}
