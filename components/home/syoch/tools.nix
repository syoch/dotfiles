{ components, pkgs, ... }:
{
  imports = [
    (components + /tool/git)
    (components + /tool/ssh)
    (components + /tool/syncthing)
  ];

  home.packages = with pkgs; [
    zydis
    ghq
    dive
    gdb
    binwalk
    cling

    hyprlang
    hyprls
    nixd
    nixfmt-rfc-style

    brightnessctl

    hexyl
    neofetch
    sshfs
    inkscape
    maxima
    ddcutil
    i2c-tools

    # network
    netdiscover
    socat
    websocat
  ];
}
