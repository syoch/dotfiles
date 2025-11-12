{ pkgs, ... }:
{
  home.username = "syoch";
  home.homeDirectory = "/home/syoch";
  home.stateVersion = "25.05";
  nixpkgs.config.allowUnfree = true;
  programs.home-manager.enable = true;

  imports = [
    # ./audio.nix
  ];

  #* Desktop environment
  hm-module.theme-setting.enable = true;
  hm-module.hyprland.enable = true; # DE
  hm-module.ags.enable = true; # Bar Implementation
  hm-module.mako.enable = true; # Notifications
  hm-module.wayvnc.enable = true; # VNC Server
  hm-module.i18n.enable = true;

  # Apps
  hm-module.zsh.enable = true;
  hm-module.nvim.enable = true;
  hm-module.tmux.enable = true;
  hm-module.git.enable = true;
  hm-module.ssh.enable = true;
  hm-module.wezterm.enable = true;
  hm-module.firefox.enable = true;
  hm-module.obs-studio.enable = true;
  hm-module.winapps.enable = true;
  hm-module.syncthing.enable = true;
  hm-module.prismlauncher.enable = true;
  programs.joplin-desktop.enable = true;
  programs.vscode.enable = true;
  programs.wofi.enable = true;

  home.packages = with pkgs; [
    nwg-displays
    nwg-look
    vlc

    ghidra
    pavucontrol

    p7zip
  ];

}
