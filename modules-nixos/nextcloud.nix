{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.os-mod.nextcloud;
in
{
  options.os-mod.nextcloud = {
    enable = lib.mkEnableOption "Nextcloud service.";
    hostName = lib.mkOption {
      type = lib.types.str;
      description = "The hostname for the Nextcloud instance.";
    };
    dataDirectory = lib.mkOption {
      type = lib.types.str;
      description = "Path to Nextcloud data directory.";
    };
    adminPasswordSecretName = lib.mkOption {
      type = lib.types.str;
      default = "nextcloud-admin-password";
      description = "The name of the sops secret containing the Nextcloud admin password.";
    };
    adminPasswordSecretPath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nextcloud-admin-password";
      description = "The path where the Nextcloud admin password secret is stored.";
    };
    envSecretName = lib.mkOption {
      type = lib.types.str;
      default = "nextcloud-env";
      description = "The name of the sops secret containing the Nextcloud environment variables.";
    };
    envSecretPath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nextcloud-env";
      description = "The path where the Nextcloud environment variables secret is stored.";
    };

    config = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional Nextcloud configuration options.";
    };

    listen = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule (
          { ... }:
          {
            options = {
              addr = lib.mkOption {
                type = lib.types.str;
                description = "The address to listen on.";
              };
              port = lib.mkOption {
                type = lib.types.int;
                description = "The port to listen on.";
              };
            };
          }
        )
      );
      default = [
        {
          addr = "localhost";
          port = 8080;
        }
      ];
      description = "The addresses and ports for Nextcloud to listen on.";
    };
  };
  config = lib.mkIf cfg.enable {
    services.nextcloud.enable = true;
    services.nextcloud.package = pkgs.nextcloud33;
    services.nextcloud.hostName = cfg.hostName;
    services.nextcloud.database.createLocally = true;
    services.nextcloud.config.dbtype = "pgsql";
    services.nextcloud.settings.datadirectory = cfg.dataDirectory;
    services.nextcloud.maxUploadSize = "1G";
    services.nextcloud.extraApps = {
      inherit (pkgs.nextcloud33Packages.apps) calendar tasks whiteboard;
      inherit (pkgs.nextcloud33Packages.apps) deck previewgenerator;
    };
    services.nextcloud.appstoreEnable = true;

    sops.secrets."${cfg.adminPasswordSecretName}" = {
      owner = "root";
      path = cfg.adminPasswordSecretPath;
    };
    services.nextcloud.config.adminpassFile = cfg.adminPasswordSecretPath;

    sops.secrets."${cfg.envSecretName}" = {
      owner = "root";
      path = cfg.envSecretPath;
    };
    systemd.services.nextcloud-custom-config = {
      path = [ config.services.nextcloud.occ ];
      script = ''
        source ${cfg.envSecretPath}
        ${cfg.config}
      '';
      after = [ "nextcloud-setup.service" ];
      wantedBy = [ "multi-user.target" ];
    };

    services.nginx.clientMaxBodySize = "0";
    services.nginx.virtualHosts."${config.services.nextcloud.hostName}" = {
      listen = cfg.listen;
      extraConfig = ''
        # Large file transfer support
        client_body_timeout 3600s;
        send_timeout 3600s;
        keepalive_timeout 3600s;
        proxy_connect_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_read_timeout 3600s;
      '';
    };

    os-mod.nas.enableGroups = true;
    os-mod.nas.nasUsers = [ "nextcloud" ];
  };
}
