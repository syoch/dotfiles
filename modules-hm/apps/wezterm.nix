{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.hm-module.wezterm;
in
{
  options.hm-module.wezterm = {
    enable = lib.mkEnableOption "wezterm";
  };

  config = lib.mkIf cfg.enable {
    hm-module.nixgl.enable = true;

    programs.wezterm = {
      enable = true;
      package = (config.lib.nixGL.wrap pkgs.wezterm);
    };

    home.file.".config/wezterm".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/config/wezterm";
  };
}
