{
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.hm-module.syncthing;
in
{
  options.hm-module.syncthing = {
    enable = mkEnableOption "syncthing";
  };

  config = mkIf cfg.enable {
    services.syncthing.enable = true;
  };
}
