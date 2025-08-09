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
}
