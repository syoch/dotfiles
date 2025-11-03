{ pkgs, config, ... }:
{
  home.file.".config/hypr".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/config/hypr";

  # Screen shot
  home.packages = with pkgs; [
    grim
    slurp
    wl-clipboard
    libnotify
  ];

  systemd.user.services."wayland-output@" = {
    Unit = {
      Description = "Add headless output for hyprland %i";
    };
    Service = {
      ExecStart = "/usr/bin/hyprctl output create headless %i";
      ExecStop = "/usr/bin/hyprctl output remove %i";
    };
  };

  home.sessionVariables.XDG_SESSION_TYPE = "wayland";
  home.sessionVariables.MOZ_ENABLE_WAYLAND = "1";
  home.sessionVariables.QT_QPA_PLATFORM = "wayland;xcb";
  home.sessionVariables.XDG_CURRENT_DESKTOP = "sway";
  home.sessionVariables.XDG_CURRENT_SESSION = "sway";
  home.sessionVariables.LIBSEAT_BACKEND = "logind";
  home.sessionVariables.GDK_DPI_SCALE = "1";
  home.sessionVariables.QT_SCALE_FACTOR = "1";
  home.sessionVariables.WLR_DRM_NO_MODIFIERS = "1";
}
