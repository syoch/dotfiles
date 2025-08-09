{ components, pkgs, ... }:
{
  imports = [
    (components + /app/firefox)
    (components + /app/obs)
    (components + /app/wezterm)
  ];

  home.packages = with pkgs; [
    nwg-displays
    nwg-look
    vlc

    ghidra
    keepassxc
    pavucontrol
  ];

  programs.joplin-desktop.enable = true;
  programs.vscode.enable = true;
  programs.wofi.enable = true;
}
