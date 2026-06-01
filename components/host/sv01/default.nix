{ config, pkgs, ... }:

{
  system.stateVersion = "25.11";

  imports = [
    ./hardware-configuration.nix
    ./secrets.nix
    ./vpn.nix
    ./cloudflared.nix
    ./nextcloud.nix
  ];

  # Config
  os-mod.system.enable = true;
  os-mod.system.allowWheelToRunSudo = true;

  os-mod.user-syoch.enable = true;

  os-mod.tailscale.enable = true;
  services.tailscale.extraSetFlags = [ "--advertise-routes=10.42.0.0/16" ];
  os-mod.sshd.enable = true;

  programs.tmux.enable = true;

  networking.hostName = "syoch-sv01";
  networking.networkmanager.enable = true;

  services.cloudflared.enable = true;
  fileSystems."/boot/efi".options = [ "nofail" ];

  services.nextcloud.settings.trusted_domains = [
    "localhost"
    "10.42.0.1"
  ];

  users.groups.nas-agent = { };
  users.users.syoch.extraGroups = [ "nas-agent" ];
  users.users.nextcloud.extraGroups = [ "nas-agent" ];
  security.sudo.wheelNeedsPassword = false;

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

  services.collabora-online = {
    enable = true;
    settings.storage.wopi = {
      "@allow" = true;
      host = [
        "collabora.syoch.org"
      ];
    };
  };

  virtualisation.podman.enable = true;
  systemd.tmpfiles.rules = [
    "d /srv/xwiki 0700 999 999 - -"
  ];
  services.postgresql = {
    ensureDatabases = [ "xwiki" ];
    ensureUsers = [
      {
        name = "xwiki";
        ensureDBOwnership = true;
      }
    ];
    enableTCPIP = true;
    authentication = ''
      host xwiki xwiki 10.88.0.1/16 scram-sha-256
    '';
  };
  networking.firewall.interfaces."podman0".allowedTCPPorts = [ 5432 ];
  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers.xwiki = {
    image = "docker.io/library/xwiki:lts-postgres-tomcat";
    ports = [ "8080:8080" ];

    environment = {
      DB_USER = "xwiki";
      DB_PASSWORD = "your_secret_password";
      DB_HOST = "10.88.0.1";
      DB_DATABASE = "xwiki";
    };

    volumes = [
      "/srv/xwiki:/usr/local/xwiki"
    ];
  };

  services.syoch-portal = {
    enable = true;
    configFile = pkgs.writeText "config.json" (
      builtins.toJSON {
        database = {
          url = "sqlite:////srv/syoch-portal/database.db";
          sqlite_wal = true;
        };
        server = {
          port = 8000;
          host = "127.0.0.1";
        };
        extensions = [
          {
            module = "servers.storage_manager";
            class = "StorageManagerExtension";
            config = {
              uploads_dir = "/srv/syoch-portal/uploads";
            };
          }
          {
            module = "servers.obtainium_repo";
            class = "ObtainiumRepoExtension";
          }
        ];
      }
    );

    readWritePaths = [
      "/srv/syoch-portal"
    ];
  };

  environment.systemPackages = with pkgs; [
    neovim
    wget
    podman
  ];
}
