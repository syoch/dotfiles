{ config, pkgs, ... }:
{
  programs.wezterm = {
    enable = true;
    package = (config.lib.nixGL.wrap pkgs.wezterm);
  };

  home.file.".config/wezterm".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/components/app/wezterm/config";
}
