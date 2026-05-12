{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.hm-module.nvim;
  mkOutOfStoreSymlink = config.lib.file.mkOutOfStoreSymlink;
in
{
  options.hm-module.nvim = {
    enable = mkEnableOption "nvim";
  };

  config = mkIf cfg.enable {
    programs.neovim = {
      enable = false;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      withRuby = false;
      withPython3 = true;
      vimdiffAlias = true;
    };
    home.packages = [ pkgs.neovim ];
    xdg.configFile."nvim".source = mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/nvim";
  };
}
