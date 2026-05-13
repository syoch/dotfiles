{
  lib,
  config,
  pkgs,
  ...
}:
{
  options.shell = {
    enable = lib.mkOption {
      type = lib.types.bool;
      description = "Whether to enable the shell module.";
      default = false;
    };

    shellHooks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "List of shell hook scripts to be sourced in the shell.";
      default = [ ];
    };
  };

  config = lib.mkIf config.shell.enable {
    environment.packages = [
      pkgs.zsh
    ];

    user.shell = "${pkgs.zsh}/bin/zsh";
    environment.etc."zshrc".text = lib.concatStringsSep "\n" (config.shell.shellHooks);
  };
}
