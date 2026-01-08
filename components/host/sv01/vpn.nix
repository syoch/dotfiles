{ pkgs, ... }:
{
  networking.networkmanager.ensureProfiles.profiles."VPN" = {
    connection = {
      id = "VPN";
      interface-name = "wg-vpn";
      type = "wireguard";
    };
    ipv4 = {
      address1 = "10.2.0.2/32";
      ignore-auto-dns = "true";
      ignore-auto-routes = "true";
      may-fail = "false";
      method = "manual";
      never-default = "true";
      route1 = "192.200.0.0/24";
      route2 = "3.33.139.32/32"; # ipconfig.me
    };
    wireguard = {
      listen-port = "$vpn_listen_port";
      private-key = "$vpn_private_key";
    };
    "wireguard-peer.$vpn_public_key" = {
      allowed-ips = "0.0.0.0/0;";
      endpoint = "$vpn_endpoint";
    };
  };
  networking.firewall.trustedInterfaces = [ "wg-vpn" ];

  environment.systemPackages = [ pkgs.wireguard-tools ];
}
