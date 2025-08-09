{ pkgs, config, ... }:
{
  fonts.fontconfig.enable = true;

  home.packages = with pkgs; [
    nerd-fonts.fira-code
    noto-fonts
    noto-fonts-cjk-sans
  ];

  home.file.".local/share/fonts/Firple-Italic.ttf" = {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/Assets/Firple-Italic.ttf";
  };
  home.file.".local/share/fonts/Firple-Regular.ttf" = {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/Assets/Firple-Regular.ttf";
  };
  home.file.".local/share/fonts/Firple-Bold.ttf" = {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/Assets/Firple-Bold.ttf";
  };
  home.file.".local/share/fonts/Firple-BoldItalic.ttf" = {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/Assets/Firple-BoldItalic.ttf";
  };
}
