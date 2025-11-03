{
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.os-mod.pipewire;
in
{
  options.os-mod.pipewire = {
    enable = mkEnableOption "pipewire";
  };

  config = mkIf cfg.enable {
    services.pipewire = {
      enable = true;
      pulse.enable = true;
      alsa.enable = true;
    };
  };
}
