{ config, pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.cloudflared
  ];
  # Nextcloud + Portal tunnel
  # (CF dashboard already has portal.syoch.org routed to this tunnel;
  #  the local ingress below mirrors the dashboard config so cloudflared
  #  does not 404 on the connection from CF edge.)
  services.cloudflared = {
    enable = true;
    certificateFile = config.sops.secrets."cloudflared-account-cred".path;

    tunnels."nextcloud" = {
      credentialsFile = config.sops.secrets."cloudflared-tunnel-cred-nextcloud".path;
      default = "http_status:404";
      ingress = {
        "nextcloud.syoch.org" = "http://127.0.0.1:8080";
        "wb-nextcloud.syoch.org" = "http://127.0.0.1:3002";
        "collabora.syoch.org" = "http://127.0.0.1:9980";
        "portal.syoch.org" = "http://127.0.0.1:80";
      };
    };
  };
}
