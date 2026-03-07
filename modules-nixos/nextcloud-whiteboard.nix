{
  lib,
  config,
  ...
}:
let
  cfg = config.os-mod.nextcloud.whiteboard;
in
{
  options.os-mod.nextcloud.whiteboard = {
    enable = lib.mkEnableOption "Nextcloud whiteboard app.";
    nextcloudUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://${config.os-mod.nextcloud.hostName}/";
      description = "The URL of the Nextcloud instance.";
    };
    whiteboardUrl = lib.mkOption {
      type = lib.types.str;
      description = "The URL of the Nextcloud whiteboard server.";
    };
    secretName = lib.mkOption {
      type = lib.types.str;
      default = "nextcloud-whiteboard";
      description = "The name of the sops secret containing the Nextcloud whiteboard JWT secret key.";
    };
    secretPath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nextcloud-whiteboard-env";
      description = "The path where the Nextcloud whiteboard JWT secret key is stored.";
    };
    envJwtSecretKeyName = lib.mkOption {
      type = lib.types.str;
      default = "NEXTCLOUD_WHITEBOARD_JWT_SECRET_KEY";
      description = "The environment variable name for the Nextcloud whiteboard JWT secret key.";
    };
  };
  config = lib.mkIf cfg.enable {
    sops.secrets."${cfg.secretName}" = {
      owner = "root";
      path = cfg.secretPath;
    };

    services.nextcloud-whiteboard-server = {
      enable = true;
      settings.NEXTCLOUD_URL = "${cfg.nextcloudUrl}";
      secrets = [ "${cfg.secretPath}" ];
    };

    os-mod.nextcloud.config = ''
      nextcloud-occ config:app:set whiteboard collabBackendUrl --value="${cfg.whiteboardUrl}"
      nextcloud-occ config:app:set whiteboard jwt_secret_key --value="$${cfg.envJwtSecretKeyName}"
    '';
  };
}
