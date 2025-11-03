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

    home.file.".local/share/PrismLauncher/instances".source =
      config.lib.file.mkOutOfStoreSymlink "/mnt/usbssd/NAS/Apps/_Game/PolyMC-Windows-Portable-1.4.3/instances";
  };
}
