{
  lib,
  config,
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
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;
    };
    home.file.".config/nvim".source = mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/nvim";
  };
}
