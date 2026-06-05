{ pkgs, ... }:
{
  # Greeter
  services.xserver.enable = true;
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
  programs.xwayland.enable = true;
  programs.dconf.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "*";
  };

  # Hypr
  programs.hyprland.enable = true;
  programs.hyprland.withUWSM = true;
  programs.hyprlock.enable = true;
  services.hypridle.enable = true;
  environment.systemPackages = [
    pkgs.hyprcursor
  ];

  programs.thunderbird.enable = true;

  # Thunar
  programs.xfconf.enable = true;
  programs.thunar.enable = true;
  programs.thunar.plugins = with pkgs; [
    thunar-archive-plugin
    thunar-volman
    tumbler
  ];

  services.gvfs.enable = true;
  services.gvfs.package = pkgs.gnome.gvfs;

  # Font
  fonts = {
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-serif
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      nerd-fonts.fira-code
    ];
    fontDir.enable = true;
    fontconfig = {
      defaultFonts = {
        serif = [
          "Noto Serif CJK JP"
          "Noto Color Emoji"
        ];
        sansSerif = [
          "Noto Sans CJK JP"
          "Noto Color Emoji"
        ];
        monospace = [
          "FiraCode Nerd Font"
          "Noto Color Emoji"
        ];
        emoji = [ "Noto Color Emoji" ];
      };
    };
  };
}
