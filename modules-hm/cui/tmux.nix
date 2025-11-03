{
  pkgs,
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.hm-module.tmux;
in
{
  options.hm-module.tmux = {
    enable = mkEnableOption "tmux";
  };

  config = mkIf cfg.enable {
    programs.tmux = {
      enable = true;
      mouse = true;
      clock24 = true;
      escapeTime = 0;
      plugins = with pkgs; [
        tmuxPlugins.sensible
        tmuxPlugins.power-theme
        tmuxPlugins.pain-control
      ];
      extraConfig = ''
        set -g default-terminal "xterm-256color"
        set -ga terminal-overrides ",*256col*:Tc"
        set -ga terminal-overrides '*:Ss=\E[%p1%d q:Se=\E[ q'
        set-environment -g COLORTERM "truecolor"

        unbind %
        unbind '"'
        bind - split-window -v
        bind | split-window -h
      '';
    };
  };
}
