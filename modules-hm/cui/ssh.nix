{
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.hm-module.ssh;
in
{
  options.hm-module.ssh = {
    enable = mkEnableOption "ssh";
  };

  config = mkIf cfg.enable {
    programs.ssh.enable = true;
    programs.ssh.enableDefaultConfig = false;
    programs.ssh.matchBlocks."*" = { };
    programs.ssh.extraConfig = ''
      Include /home/syoch/.ssh/config.d/*
    '';
  };
}
