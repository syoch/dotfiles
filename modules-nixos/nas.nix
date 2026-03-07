{
  lib,
  config,
  ...
}:
let
  cfg = config.os-mod.nas;
in
{
  options.os-mod.nas = {
    enableGroups = lib.mkEnableOption "NAS user groups";
    nasUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of users to be added to the nas-agent group.";
    };
  };

  config = lib.mkIf cfg.enableGroups {
    users.groups.nas-agent = { };
    users.users = lib.foldl' (
      acc: userName:
      acc
      // {
        "${userName}" = {
          extraGroups = [ "nas-agent" ];
        };
      }
    ) { } cfg.nasUsers;
  };
}
