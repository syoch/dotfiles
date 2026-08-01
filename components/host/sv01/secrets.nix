{ config, ... }:
{
  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.sshKeyPaths = [
    "/etc/nixos/sv01.key"
  ];
  sops.secrets."networking" = {
    owner = "root";
    path = "/etc/nixos/sv01.nw.env";
  };
  networking.networkmanager.ensureProfiles.environmentFiles = [
    config.sops.secrets."networking".path
  ];
}
