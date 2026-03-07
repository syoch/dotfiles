{
  lib,
  config,
  ...
}:
let
  cfg = config.os-mod.nfs-client;
  nfsMountModule = lib.types.submodule (
    { ... }:
    {
      options = {
        what = lib.mkOption {
          type = lib.types.str;
          description = "The NFS server and export path.";
        };
        options = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "noatime" ];
          description = "Mount options.";
        };
      };
    }
  );
in
{
  options.os-mod.nfs-client = {
    enable = lib.mkEnableOption "NFS client.";
    mounts = lib.mkOption {
      type = lib.types.attrsOf nfsMountModule;
      default = { };
      description = "NFS mounts to configure.";
    };
  };
  config = lib.mkIf cfg.enable {
    services.rpcbind.enable = true;
    systemd.mounts = lib.mapAttrsToList (name: subCfg: {
      type = "nfs";
      mountConfig.Options = lib.concatStringsSep "," subCfg.options;
      what = subCfg.what;
      where = name;
    }) cfg.mounts;

    systemd.automounts = lib.mapAttrsToList (name: subCfg: {
      wantedBy = [ "multi-user.target" ];
      automountConfig.TimeoutIdleSec = "600";
      where = name;
    }) cfg.mounts;
  };
}
