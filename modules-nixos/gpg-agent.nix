{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.os-mod.gnupg;
in
{
  options.os-mod.gnupg = {
    enable = lib.mkEnableOption "gnupg";
  };

  config = lib.mkIf cfg.enable {
    programs.gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };

    environment.systemPackages = with pkgs; [
      gnupg
    ];
  };
}
