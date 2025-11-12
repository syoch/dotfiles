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

    gtk = {
      enable = true;
      iconTheme = {
        package = pkgs.adwaita-icon-theme;
        name = "Adwaita";
      };
      theme = {
        package = pkgs.adwaita-qt;
        name = "Adwaita";
      };
    };
  };
}
