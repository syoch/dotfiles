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
      hashedPassword = "$y$j9T$5x0E/cmThaqlolxfL2VbO1$yDRoNC4kqm10AkGMK8BNqYFZYcpLH9ltSIylUJGdvo6";
    };
  };
}
