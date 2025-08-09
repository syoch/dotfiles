{ pkgs, config, ... }:
{
  sops.secrets."syoch-pw".neededForUsers = true;

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
}
