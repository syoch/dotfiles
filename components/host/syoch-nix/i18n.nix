{ lib, ... }:
{
  time.timeZone = "Asia/Tokyo";
  i18n.defaultLocale = "ja_JP.UTF-8";

  console = {
    font = "Lat2-Terminus16";
    keyMap = lib.mkForce "jp106";
    useXkbConfig = true; # use xkb.options in tty.
  };
}
