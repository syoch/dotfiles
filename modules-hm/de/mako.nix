{
  pkgs,
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.hm-module.mako;
in
{
  options.hm-module.mako = {
    enable = mkEnableOption "mako";
  };

  config = mkIf cfg.enable {
    services.mako.enable = true;
    systemd.user.services.mako = {
      Unit = {
        Description = "Launch mako";
      };
      Service = {
        ExecStart = "${pkgs.mako}/bin/mako";
      };
    };
  };
}
