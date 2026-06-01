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
    };
  };
}
