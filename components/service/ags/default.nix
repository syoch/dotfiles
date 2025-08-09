{
  pkgs,
  config,
  inputs,
  ...
}:
let
  home = config.home.homeDirectory;
in
{
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
      ExecStart = "/etc/profiles/per-user/syoch/bin/ags run ${home}/dotfiles/config/ags/app.ts";
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
    ExecStart=/run/current-system/sw/bin/systemctl --user restart ags.service
  '';
}
