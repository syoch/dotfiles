{
  pkgs,
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.hm-module.wayvnc;
in
{
  options.hm-module.wayvnc = {
    enable = mkEnableOption "wayvnc";
  };

  config = mkIf cfg.enable {
    services.wayvnc.enable = true;
    services.wayvnc.settings.address = "0.0.0.0";
    services.wayvnc.settings.port = 5901;

    systemd.user.services."wayland-vnc@" = {
      Unit.Description = "WayVNC service for output %i";
      Service.ExecStart = "${pkgs.wayvnc}/bin/wayvnc -o %i 0.0.0.0";
      Install.Requires = [ "wayland-output@%i.service" ];
    };
  };
}
