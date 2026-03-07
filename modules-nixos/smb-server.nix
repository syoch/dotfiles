{ config, lib, ... }:
{
  options.os-mod.smb-server = {
    enable = lib.mkEnableOption "Samba SMB server.";
    allowedIPs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "127.0.0.1"
        "localhost"
      ];
      description = "List of IPs allowed to access the SMB server.";
    };
    validUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of valid users for SMB authentication.";
    };
    serverName = lib.mkOption {
      type = lib.types.str;
      default = "NixOS";
      description = "The NetBIOS name of the SMB server.";
    };
    folders = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { ... }:
          {
            options = {
              path = lib.mkOption {
                type = lib.types.str;
                description = "The path to the shared folder.";
              };
              browseable = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Whether the share is browseable.";
              };
              readOnly = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Whether the share is read-only.";
              };
              createMask = lib.mkOption {
                type = lib.types.str;
                default = "0644";
                description = "The create mask for files in the share.";
              };
              directoryMask = lib.mkOption {
                type = lib.types.str;
                default = "0755";
                description = "The directory mask for directories in the share.";
              };
            };
          }
        )
      );
      default = { };
      description = "Shared folders configuration.";
    };
  };

  config = lib.mkIf config.os-mod.smb-server.enable {
    services.samba = {
      enable = true;
      securityType = "user";
      openFirewall = true;
      settings = {
        global = {
          "workgroup" = "WORKGROUP";
          "server string" = config.os-mod.smb-server.serverName;
          "netbios name" = config.os-mod.smb-server.serverName;
          "security" = "user";
          "valid users" = lib.concatStringsSep " " config.os-mod.smb-server.validUsers;
          "hosts allow" = lib.concatStringsSep " " (config.os-mod.smb-server.allowedIPs);
          "hosts deny" = "0.0.0.0/0";
        };
      }
      // lib.mapAttrs (key: subCfg: {
        path = subCfg.path;
        browseable = if subCfg.browseable then "yes" else "no";
        "read only" = if subCfg.readOnly then "yes" else "no";
        "create mask" = subCfg.createMask;
        "directory mask" = subCfg.directoryMask;
      }) config.os-mod.smb-server.folders;
    };
    services.samba-wsdd = {
      enable = true;
      openFirewall = true;
    };
  };
}
