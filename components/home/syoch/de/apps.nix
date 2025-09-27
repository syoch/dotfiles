{ components, pkgs, ... }:
{
  imports = [
    (components + /app/wezterm)
  ];

  programs.firefox.languagePacks = [
    "jp"
    "ja-JP"
  ];

  programs.obs-studio = {
    plugins = with pkgs.obs-studio-plugins; [
      wlrobs
      obs-backgroundremoval
      obs-pipewire-audio-capture
      obs-gstreamer
      obs-vaapi
    ];
  };

  home.packages = with pkgs; [
    nwg-displays
    nwg-look
    vlc

    ghidra
    pavucontrol
  ];

  programs.joplin-desktop.enable = true;
  programs.vscode.enable = true;
  programs.wofi.enable = true;
}
