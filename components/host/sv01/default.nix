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
  security.sudo.wheelNeedsPassword = true;

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
    "d /srv/syoch-portal 0700 syoch-portal syoch-portal - -"
  ];
  services.postgresql = {
    ensureDatabases = [
      "xwiki"
      "syoch-portal"
    ];
    ensureUsers = [
      {
        name = "xwiki";
        ensureDBOwnership = true;
      }
      {
        name = "syoch-portal";
        ensureDBOwnership = true;
      }
    ];
    enableTCPIP = true;
    authentication = ''
      host xwiki xwiki 10.88.0.1/16 scram-sha-256
      host syoch-portal syoch-portal 127.0.0.1/32 scram-sha-256
      host postgres postgres 10.42.0.0/16 scram-sha-256
    '';
  };
  networking.firewall.interfaces."podman0".allowedTCPPorts = [ 5432 ];
  virtualisation.oci-containers.backend = "podman";
  sops.secrets."portal-db-password" = {
    owner = "postgres";
    path = "/etc/nixos/portal-db-password";
  };
  sops.secrets."xwiki-db-password" = {
    owner = "postgres";
    path = "/etc/nixos/xwiki-db-password";
  };
  systemd.services.postgresql-setup-passwords = {
    description = "Set PostgreSQL passwords from SOPS secrets";
    path = [ pkgs.postgresql ];

    requires = [ "postgresql.service" ];
    after = [ "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];
    before = [ "syoch-portal.service" ];

    serviceConfig = {
      User = "postgres";
      Group = "postgres";
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      set -e
      xwiki_password="$(cat ${config.sops.secrets."xwiki-db-password".path})"
      portal_password="$(cat ${config.sops.secrets."portal-db-password".path})"
      psql -v ON_ERROR_STOP=1 -c "ALTER USER \"xwiki\" WITH PASSWORD '$xwiki_password';"
      psql -v ON_ERROR_STOP=1 -c "ALTER USER \"syoch-portal\" WITH PASSWORD '$portal_password';"
    '';
  };
  sops.secrets."xwiki-env" = {
    owner = "root";
    path = "/etc/nixos/xwiki-env";
  };
  virtualisation.oci-containers.containers.xwiki = {
    image = "docker.io/library/xwiki:lts-postgres-tomcat";
    ports = [ "8080:8080" ];

    environmentFiles = [
      config.sops.secrets."xwiki-env".path
    ];

    volumes = [
      "/srv/xwiki:/usr/local/xwiki"
    ];
  };

  sops.secrets."portal-config" = {
    owner = "syoch-portal";
    path = "/etc/nixos/portal-config";
  };

  services.syoch-portal = {
    enable = true;
    configFile = config.sops.secrets."portal-config".path;

    user = "syoch-portal";
    group = "syoch-portal";
  };
  systemd.services.syoch-portal = {
    requires = [ "postgresql-setup-passwords.service" ];
    after = [ "postgresql-setup-passwords.service" ];
  };
  services.nginx.clientMaxBodySize = "1G";
  services.nginx.recommendedProxySettings = true;
  services.nginx.recommendedTlsSettings = true;
  services.nginx.virtualHosts."portal.syoch.org" = {
    listenAddresses = [
      "127.0.0.1"
      "100.96.100.1"
    ];
    extraConfig = ''
      add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
      add_header X-Frame-Options "DENY" always;
      add_header X-Content-Type-Options "nosniff" always;
      add_header Referrer-Policy "no-referrer" always;
      add_header Permissions-Policy "interest-cohort=()" always;
      add_header Content-Security-Policy "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'" always;
    '';
    locations."/" = {
      proxyPass = "http://127.0.0.1:8000";
      proxyWebsockets = true;
    };
  };

  environment.systemPackages = with pkgs; [
    neovim
    wget
    podman
  ];
}
