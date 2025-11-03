{
  lib,
  config,
  ...
}:
let
  cfg = config.os-mod.i18n-jp;
in
{
  options.os-mod.i18n-jp = {
    enable = lib.mkEnableOption "i18n-jp";
  };

  config = lib.mkIf cfg.enable {
    time.timeZone = "Asia/Tokyo";
    i18n.defaultLocale = "ja_JP.UTF-8";

    console = {
      font = "Lat2-Terminus16";
      keyMap = lib.mkForce "jp106";
      useXkbConfig = true;
    };
  };
}
