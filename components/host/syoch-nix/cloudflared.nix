{ config, pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.cloudflared
  ];
  sops.secrets."cloudflared-account-cred" = {
    owner = "root";
    path = "/etc/nixos/cfd-cert.pem";
  };
  sops.secrets."cloudflared-tunnel-cred" = {
    owner = "root";
    path = "/etc/nixos/cfd-tunnel-nextcloud.json";
  };
  services.cloudflared = {
    enable = true;
    certificateFile = config.sops.secrets."cloudflared-account-cred".path;

    tunnels."syoch-nix" = {
      credentialsFile = config.sops.secrets."cloudflared-tunnel-cred".path;
      default = "http_status:404";
      ingress = {
        "opencode.syoch.org" = "http://127.0.0.1:12000";
        "code.syoch.org" = "http://127.0.0.1:9101";
        "procon.syoch.org" = "http://127.0.0.1:10001";
      };
    };
  };
}
