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
    nixGL.packages = import nixgl { inherit pkgs; };
    nixGL.defaultWrapper = "mesa"; # or whatever wrapper you need
    nixGL.installScripts = [ "mesa" ];
  };
}
