{
  pkgs,
  ...
}:
{
  imports = [
    ./hyprland.nix
    ./fonts.nix
    ./apps.nix
  ];

  hm-module.de-services.enable = true;
  hm-module.gtk.enable = true;
  hm-module.i18n.enable = true;
}
