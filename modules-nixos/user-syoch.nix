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
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILacK4KYMvzARCSG8v7H8KCeZIzXapkNB0ZwI70GaasV syoch-MyDevices"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBzarRB8V8RX0C2AGP6OqE3MUuLlq6AS8ygtao6+Hzif syoch@syoch-nix (recovery key for sv01)"
      ];
    };
  };
}
