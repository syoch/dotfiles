{
  pkgs,
  ...
}:
{
  imports = [
    ./hyprland.nix
    ./fonts.nix
    ./gtk.nix
    ./services.nix
    ./apps.nix
  ];

  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      fcitx5-nord
      fcitx5-mozc
      fcitx5-gtk
    ];
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
