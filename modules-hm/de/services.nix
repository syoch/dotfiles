{
  lib,
  config,
  ...
}:
let
  cfg = config.hm-module.de-services;
in
{
  options.hm-module.de-services = {
    enable = lib.mkEnableOption "de-services";
  };

  config = lib.mkIf cfg.enable {
    hm-module.ags.enable = true;
    hm-module.mako.enable = true;
    services.hyprpaper.enable = true;

    systemd.user.targets.hyprland-services = {
      Unit = {
        Description = "Hyprland services (Userland)";
        Requires = [
          "ags.service"
          "ags-restart.path"
          "mako.service"
          "hyprpaper.service"
        ];
      };
    };
  };
}
