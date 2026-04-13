{ config, pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.cloudflared
  ];
  # Nextcloud tunnel
  services.cloudflared = {
    enable = true;
    certificateFile = config.sops.secrets."cloudflared-account-cred".path;

    tunnels."nextcloud" = {
      credentialsFile = config.sops.secrets."cloudflared-tunnel-cred-nextcloud".path;
      default = "http_status:404";

      ingress."nextcloud.syoch.org".service = "http://127.0.0.1:8080";
      ingress."wb-nextcloud.syoch.org".service = "http://127.0.0.1:3002";
    };
  };
}
