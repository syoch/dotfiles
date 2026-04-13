{ config, pkgs, ... }:

{
  system.stateVersion = "25.11";

  imports = [
    ./hardware-configuration.nix
    ./secrets.nix
    ./vpn.nix
    ./cloudflared.nix
  ];

  # Config
  os-mod.system.enable = true;
  os-mod.system.allowWheelToRunSudo = true;

  os-mod.user-syoch.enable = true;

  os-mod.tailscale.enable = true;
  os-mod.sshd.enable = true;

  programs.tmux.enable = true;

  networking.hostName = "syoch-sv01";
  networking.networkmanager.enable = true;

  services.cloudflared.enable = true;
  fileSystems."/boot/efi".options = [ "nofail" ];

  os-mod.nextcloud = {
    enable = true;
    hostName = "nextcloud.syoch.org";
    dataDirectory = "/srv/NAS/nextcloud";
    listen = [
      {
        addr = "localhost";
        port = 8080;
      }
      {
        addr = "10.42.0.1";
        port = 8080;
      }
    ];
  };
  services.nextcloud.settings.trusted_domains = [
    "localhost"
    "10.42.0.1"
  ];
  os-mod.nextcloud.whiteboard = {
    enable = true;
    whiteboardUrl = "https://wb-nextcloud.syoch.org";
  };

  users.groups.nas-agent = { };
  users.users.syoch.extraGroups = [ "nas-agent" ];
  users.users.nextcloud.extraGroups = [ "nas-agent" ];

  os-mod.router = {
    enable = true;
    upstream.interface = "enp0s31f6";
    downstream.interface = "enp0s20f0u4u4i5";
    downstream.ipAddress = "10.42.0.1";
    downstream.prefixLength = 16;
    downstream.dhcpRangeStart = "10.42.100.0";
    downstream.dhcpRangeEnd = "10.42.200.0";
    extraForwardableInterfaces = [ "wg-vpn" ];
  };

  os-mod.smb-server = {
    enable = true;
    serverName = "sv01";
    validUsers = [ "syoch" ];
    allowedIPs = [
      "10.42. "
      "100."
      "127.0.0.1"
      "localhost"
    ];
    folders.NAS = {
      path = "/srv/NAS";
    };
  };

  os-mod.nfs-server = {
    enable = true;
    openFirewall = true;
    exports."/srv/NAS" = {
      clients."100.96.128.3" = { };
      clients."10.42.0.0/16" = { };
    };
  };

  services.syncthing.enable = true;
  services.syncthing.settings.devices."syoch-phone".id =
    "Q7ESIWR-ID6L62Q-77AL2GT-MLXNJF5-X2EHY2R-4XCX6VH-BA7PJFS-36K4QAX";

  environment.systemPackages = with pkgs; [
    neovim
    wget
    podman
  ];
}
