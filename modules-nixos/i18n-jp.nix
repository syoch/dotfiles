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
    i18n.extraLocaleSettings = {
      LC_ADDRESS = "ja_JP.UTF-8";
      LC_IDENTIFICATION = "ja_JP.UTF-8";
      LC_MEASUREMENT = "ja_JP.UTF-8";
      LC_MONETARY = "ja_JP.UTF-8";
      LC_NAME = "ja_JP.UTF-8";
      LC_NUMERIC = "ja_JP.UTF-8";
      LC_PAPER = "ja_JP.UTF-8";
      LC_TELEPHONE = "ja_JP.UTF-8";
      LC_TIME = "ja_JP.UTF-8";
    };

    console = {
      font = "Lat2-Terminus16";
      keyMap = lib.mkForce "jp106";
      useXkbConfig = true;
    };
  };
}
