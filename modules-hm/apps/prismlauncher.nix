{
  pkgs,
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.hm-module.prismlauncher;
in
{
  options.hm-module.prismlauncher = {
    enable = mkEnableOption "prismlauncher";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      prismlauncher
    ];
  };
}
