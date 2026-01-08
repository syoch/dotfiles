{ config, ... }:
{
  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.sshKeyPaths = [
    "/home/syoch/.config/sops/age/id_syoch"
  ];
  sops.secrets."ssh-config" = {
    owner = "syoch";
    path = "/home/syoch/.ssh/config.d/secret";
  };

  sops.secrets."network-env" = { };
  networking.networkmanager.ensureProfiles.environmentFiles = [
    config.sops.secrets."network-env".path
  ];
}
