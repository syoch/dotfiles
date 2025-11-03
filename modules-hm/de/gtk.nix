{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.hm-module.gtk;
in
{
  options.hm-module.gtk = {
    enable = lib.mkEnableOption "gtk";
  };

  config = lib.mkIf cfg.enable {
    gtk = {
      enable = true;
      iconTheme = {
        package = pkgs.adwaita-icon-theme;
        name = "Adwaita";
      };
      theme = {
        package = pkgs.adwaita-qt;
        name = "Adwaita";
      };
    };
  };
}
