{ config, pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.cloudflared
  ];
  sops.secrets."cloudflared-account-cred" = {
    owner = "root";
    path = "/etc/nixos/cfd-cert.pem";
  };
  sops.secrets."cloudflared-tunnel-cred-nextcloud" = {
    owner = "root";
    path = "/etc/nixos/cfd-tunnel-nextcloud.json";
  };

  services.cloudflared = {
    enable = true;
    certificateFile = config.sops.secrets."cloudflared-account-cred".path;

    tunnels."nextcloud" = {
      credentialsFile = config.sops.secrets."cloudflared-tunnel-cred-nextcloud".path;
      default = "http_status:404";
    };
  };
}
