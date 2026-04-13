{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.hm-module.theme-setting;
  mkCustomFont = name: {
    ".local/share/fonts/${name}" = {
      source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/Assets/${name}";
    };
  };
  mkCustomFonts = names: lib.foldl' (acc: name: acc // mkCustomFont name) { } names;
in
{
  options.hm-module.theme-setting = {
    enable = lib.mkEnableOption "theme-setting";
  };

  config = lib.mkIf cfg.enable {
    fonts.fontconfig.enable = true;

    home.pointerCursor = {
      gtk.enable = true;
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Classic";
      size = 16;
    };

    home.file = mkCustomFonts [
      "Firple-Light.ttf"
      "Firple-LightItalic.ttf"
      "Firple-Italic.ttf"
      "Firple-Regular.ttf"
      "Firple-Bold.ttf"
      "Firple-BoldItalic.ttf"
    ];

    home.packages = with pkgs; [
      nerd-fonts.fira-code
      noto-fonts
      noto-fonts-cjk-sans
    ];

    gtk =
      let
        theme = {
          package = pkgs.orchis-theme;
          name = "Orchis-Grey-Dark";
        };
      in
      {
        enable = true;
        theme = theme;

        iconTheme = {
          package = pkgs.tela-icon-theme;
          name = "Tela-blue-dark";
        };

        gtk4.theme = theme;
        gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
        gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
      };

  };
}
