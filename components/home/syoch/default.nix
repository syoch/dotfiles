{
  nixgl,
  config,
  pkgs,
  ...
}:
{
  home.username = "syoch";
  home.homeDirectory = "/home/syoch";
  home.stateVersion = "25.05";

  imports = [
    # ./audio.nix
    ./de
  ];

  hm-module.zsh.enable = true;
  hm-module.nvim.enable = true;
  hm-module.tmux.enable = true;

  hm-module.git.enable = true;
  hm-module.ssh.enable = true;
  hm-module.syncthing.enable = true;

  hm-module.winapps.enable = true;
  hm-module.prismlauncher.enable = true;

  nixGL.packages = import nixgl { inherit pkgs; };
  nixGL.defaultWrapper = "mesa"; # or whatever wrapper you need
  nixGL.installScripts = [ "mesa" ];

  nixpkgs.config.allowUnfree = true;

  programs.home-manager.enable = true;
}
