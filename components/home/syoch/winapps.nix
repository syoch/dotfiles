{ inputs, pkgs, ... }:
{
  home.packages = [
    inputs.winapps.packages."x86_64-linux".winapps
    inputs.winapps.packages."x86_64-linux".winapps-launcher
    pkgs.freerdp
  ];

  home.file.".config/winapps/winapps.conf".text = ''
    RDP_USER=winapps
    RDP_PASS=winapps

    FREERDP_COMMAND="~/.config/winapps/freerdp-wrapper"
    RDP_IP=127.0.0.1
    RDP_FLAGS="/sound /microphone +home-drive"
    MULTIMON="true"
    DEBUG="true"

    . ~/.config/winapps/overrides.conf
  '';
}
