{ components, pkgs, ... }:
{
  imports = [
    (components + /service/ags)
    (components + /service/wayvnc)
  ];

  home.packages = with pkgs; [
    novnc
  ];

  services.mako.enable = true;
  systemd.user.services.mako = {
    Unit = {
      Description = "Launch mako";
    };
    Service = {
      ExecStart = "/home/syoch/.nix-profile/bin/mako";
    };
  };

  services.hyprpaper.enable = true;

  systemd.user.targets.hyprland-services = {
    Unit = {
      Description = "Hyprland services (Userland)";
      Requires = [
        "ags.service"
        "ags-restart.path"
        "mako.service"
        "hyprpaper.service"
      ];
    };
  };

  systemd.user.services."wayland-output@tablet" = {
    Unit = {
      Description = "Add headless output for hyprland 'tablet'";
    };
    Service = {
      ExecStart = "/usr/bin/hyprctl output create headless tablet";
      ExecStop = "/usr/bin/hyprctl output remove tablet";
    };
  };
}
