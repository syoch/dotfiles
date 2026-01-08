{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.os-mod.user-syoch;
in
{
  options.os-mod.user-syoch = {
    enable = lib.mkEnableOption "syoch user";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."syoch-pw".neededForUsers = true;
    programs.zsh.enable = true;

    users.users.syoch = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "docker"
        "libvirtd"
        "dialout"
      ];
      shell = pkgs.zsh;
      hashedPasswordFile = config.sops.secrets."syoch-pw".path;
    };
  };
}
