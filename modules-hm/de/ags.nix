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

      extraPackages = with inputs.astal.packages.${pkgs.system}; [
        battery
        hyprland
        network
        tray
        wireplumber
      ];
    };

    systemd.user.services.ags = {
      Unit = {
        Description = "Wayland Bar (AGS Implementation)";
      };
      Service = {
        ExecStart = "${home}/.nix-profile/bin/ags run ${home}/dotfiles/config/ags/app.ts";
      };
    };

    home.file.".config/systemd/user/ags-restart.path".text = ''
      [Path]
      PathModified=${home}/dotfiles/config/ags/app.ts
      PathModified=${home}/dotfiles/config/ags/widget
    '';
    home.file.".config/systemd/user/ags-restart.service".text = ''
      [Unit]
      Description=Restart AGS
      After=hyprland-services.target

      [Service]
      Type=oneshot
      ExecStart=${pkgs.systemd}/sw/bin/systemctl --user restart ags.service
    '';
  };
}
