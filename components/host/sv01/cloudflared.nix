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
        "nextcloud.syoch.org" = "http://127.0.0.1:80";
        "wb-nextcloud.syoch.org" = "http://127.0.0.1:80";
        "collabora.syoch.org" = "http://127.0.0.1:80";
        "portal.syoch.org" = "http://127.0.0.1:80";
        "xwiki.syoch.org" = "http://127.0.0.1:80";
      };
    };
  };
}
