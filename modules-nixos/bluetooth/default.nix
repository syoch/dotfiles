{
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.os-mod.bluetooth;
in
{
  options.os-mod.bluetooth = {
    enable = mkEnableOption "bluetooth";
  };

  config = mkIf cfg.enable {
    hardware.bluetooth.enable = true;
    hardware.bluetooth.powerOnBoot = true;
    services.blueman.enable = true;
  };
}
