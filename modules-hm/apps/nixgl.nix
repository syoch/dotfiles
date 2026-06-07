{
  pkgs,
  lib,
  config,
  nixgl,
  ...
}:
let
  cfg = config.hm-module.nixgl;
in
{
  options.hm-module.nixgl = {
    enable = lib.mkEnableOption "nixgl";
  };

  config = lib.mkIf cfg.enable {
    targets.genericLinux.nixGL.packages = import nixgl { inherit pkgs; };
    targets.genericLinux.nixGL.defaultWrapper = "mesa"; # or whatever wrapper you need
    targets.genericLinux.nixGL.installScripts = [ "mesa" ];
  };
}
