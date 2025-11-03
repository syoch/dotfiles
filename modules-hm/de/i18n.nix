{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.hm-module.i18n;
in
{
  options.hm-module.i18n = {
    enable = lib.mkEnableOption "i18n";
  };

  config = lib.mkIf cfg.enable {
    i18n.inputMethod = {
      enable = true;
      type = "fcitx5";
      fcitx5.addons = with pkgs; [
        fcitx5-nord
        fcitx5-mozc
        fcitx5-gtk
      ];
    };
  };
}
