{ pkgs, config, ... }:
{
  sops.secrets."nextcloud-admin-password" = {
    owner = "root";
    path = "/etc/nixos/nextcloud-admin-password";
  };
  sops.secrets."nextcloud-whiteboard" = {
    owner = "root";
    path = "/etc/nixos/nextcloud-whiteboard";
  };
  sops.secrets."nextcloud-env" = {
    owner = "root";
    path = "/etc/nixos/nextcloud-env";
  };

  networking.firewall.allowedTCPPorts = [
    3002
  ];

  environment.systemPackages = [
    pkgs.imagemagick
  ];

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud33;
    hostName = "nextcloud.syoch.org";
    database.createLocally = true;
    config.dbtype = "pgsql";
    settings.datadirectory = "/srv/NAS/nextcloud";
    maxUploadSize = "2G";
    phpExtraExtensions = all: [
      all.pdlib
      all.bz2
      all.smbclient
      all.imagick
    ];
    phpOptions = {
      "max_execution_time" = "7200";
      "max_input_time" = "7200";
    };
    extraApps = {
      inherit (pkgs.nextcloud33Packages.apps) calendar tasks whiteboard;
      inherit (pkgs.nextcloud33Packages.apps) deck previewgenerator;
      ncgantt = pkgs.fetchNextcloudApp {
        url = "https://github.com/xenofex7/nextcloud-gantt/archive/9d186488518a8072837e9ab4318088335a8266b7.tar.gz";
        hash = "sha256-gozACkVIIyEqoOvT7jn1PwTDbTUDhje/Wf1wd0fRLMs=";
        license = "agpl3Only";
        patches = [
          ./ncgantt.patch
        ];
      };
    };
    appstoreEnable = true;

    config.adminpassFile = config.sops.secrets."nextcloud-admin-password".path;
    settings.trusted_domains = [
      "localhost"
      "10.42.0.1"
      "nextcloud.syoch.org"
    ];
  };

  systemd.services.nextcloud-custom-config = {
    path = [ config.services.nextcloud.occ ];
    script = ''
      source ${config.sops.secrets."nextcloud-env".path}

      function nextcloud-occ {
        /run/current-system/sw/bin/nextcloud-occ "$@"
      }

      nextcloud-occ app:enable user_ldap
      nextcloud-occ app:enable admin_audit
      nextcloud-occ app:enable deck
      nextcloud-occ app:enable previewgenerator
      nextcloud-occ app:enable calendar
      nextcloud-occ app:enable tasks
      nextcloud-occ app:enable whiteboard
      nextcloud-occ app:enable files_external
      nextcloud-occ config:app:set whiteboard collabBackendUrl --value="https://whiteboard.syoch.org"
      nextcloud-occ config:app:set whiteboard jwt_secret_key --value="$NEXTCLOUD_WHITEBOARD_JWT_SECRET_KEY"

    '';
    after = [ "nextcloud-setup.service" ];
    wantedBy = [ "multi-user.target" ];
  };

  services.nginx.virtualHosts."${config.services.nextcloud.hostName}" = {
    extraConfig = ''
      # Large file transfer support - timeouts for uploads
      client_body_timeout 3600s;
      send_timeout 3600s;
      keepalive_timeout 3600s;
      proxy_connect_timeout 3600s;
      proxy_send_timeout 3600s;
      proxy_read_timeout 3600s;
    '';
  };

  services.nextcloud-whiteboard-server = {
    enable = true;
    settings.NEXTCLOUD_URL = "https://whiteboard.syoch.org";
    secrets = [ config.sops.secrets."nextcloud-whiteboard".path ];
  };
}
