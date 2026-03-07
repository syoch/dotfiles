{
  lib,
  config,
  ...
}:
let
  cfg = config.os-mod.nfs-server;
  nfsExportModule = lib.types.submodule (
    { ... }:
    {
      options = {
        clients = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule (
              { ... }:
              {
                options = {
                  options = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [
                      "rw"
                      "sync"
                      "no_subtree_check"
                    ];
                    description = "Export options for this client.";
                  };
                };
              }
            )
          );
          default = { };
          description = "Clients and their export options.";
        };
      };
    }
  );
in
{
  options.os-mod.nfs-server = {
    enable = lib.mkEnableOption "NFS Server service.";
    exports = lib.mkOption {
      type = lib.types.attrsOf nfsExportModule;
      default = { };
      description = "NFS exports to configure.";
    };
    openFirewall = lib.mkEnableOption "Open firewall for NFS server.";
  };
  config = lib.mkIf cfg.enable {
    services.rpcbind.enable = true;
    services.nfs.server.enable = true;
    services.nfs.server.exports = lib.concatMapAttrsStringSep "\n" (
      exportName: exportCfg:
      let
        clientsStr = lib.concatMapAttrsStringSep " " (
          client: options:
          let
            optionsStr = lib.concatStringsSep "," options.options;
          in
          "${client}(${optionsStr})"
        ) exportCfg.clients;
      in
      "${exportName} ${clientsStr}"
    ) cfg.exports;

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      2049 # NFS
    ];
  };
}
