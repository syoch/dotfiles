{ pkgs, config, ... }:
{
  boot.loader.efi.efiSysMountPoint = "/boot/efi";
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.grub.device = "nodev";
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.enable = true;

  boot.extraModulePackages = [
    config.boot.kernelPackages.evdi
  ];

  boot.kernelPackages = pkgs.linuxPackages_zen;

}
