{
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.os-mod.sshd;
in
{
  options.os-mod.sshd = {
    enable = mkEnableOption "sshd";
  };

  config = mkIf cfg.enable {
    services.openssh.enable = true;
  };
}
