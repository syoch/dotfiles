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
  sops.secrets."cloudflared-account-cred" = {
    owner = "root";
    path = "/etc/nixos/cfd-cert.pem";
  };
  sops.secrets."cloudflared-tunnel-cred-nextcloud" = {
    owner = "root";
    path = "/etc/nixos/cfd-tunnel-nextcloud.json";
  };
  networking.networkmanager.ensureProfiles.environmentFiles = [
    config.sops.secrets."networking".path
  ];
}
