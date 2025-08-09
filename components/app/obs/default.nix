{ pkgs, config, ... }:
{
  programs.obs-studio = {
    enable = true;
    package = (config.lib.nixGL.wrap (pkgs.obs-studio.override { cudaSupport = true; }));
    plugins = with pkgs.obs-studio-plugins; [
      wlrobs
      obs-backgroundremoval
      obs-pipewire-audio-capture
      obs-gstreamer
      obs-vaapi
    ];
  };
}
