{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.hm-module.ags;
  home = config.home.homeDirectory;
in
{
  options.hm-module.ags = {
    enable = lib.mkEnableOption "ags";
  };

  config = lib.mkIf cfg.enable {
    programs.ags = {
      enable = true;
      systemd.enable = false;

      extraPackages = with inputs.astal.packages.${pkgs.system}; [
        battery
        hyprland
        network
        tray
        wireplumber
      ];
    };

    systemd.user.services.ags = {
      Unit.Description = "Wayland Bar (AGS Implementation)";
      Service.ExecStart = "${config.programs.ags.finalPackage}/bin/ags run ${home}/dotfiles/config/ags/app.ts";
      Install.WantedBy = [ "desktop-session.target" ];
    };

    systemd.user.paths.ags-restart = {
      Unit.Description = "Watch AGS config for changes";
      Path.PathModified = [
        "${home}/dotfiles/config/ags/app.ts"
        "${home}/dotfiles/config/ags/widget"
      ];
      Install.WantedBy = [ "desktop-session.target" ];
    };

    systemd.user.services.ags-restart = {
      Unit.Description = "Restart AGS on config change";
      Service.Type = "oneshot";
      Service.ExecStart = "${pkgs.systemd}/bin/systemctl --user restart ags.service";
    };
  };
}
