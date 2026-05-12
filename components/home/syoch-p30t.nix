{ pkgs, ... }:
{
  home.stateVersion = "25.05";

  nix.package = pkgs.nix;
  nix.settings.allow-import-from-derivation = true;

  hm-module.zsh.enable = true;
  hm-module.nvim.enable = true;
  hm-module.tmux.enable = true;
  hm-module.git.enable = true;
  hm-module.ssh.enable = true;
  hm-module.syncthing.enable = true;
  hm-module.gpg-agent.enable = true;

  programs.home-manager.enable = true;
}
