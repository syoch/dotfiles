{ pkgs, config, ... }:
{
  boot.loader.efi.efiSysMountPoint = "/boot/efi";
  boot.loader.efi.canTouchEfiVariables = true;

  boot.loader.grub.device = "nodev";
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.enable = true;
  boot.loader.grub.extraEntries = ''
    menuentry "Chainloading to systemd-boot" {
    	chainloader /EFI/systemd/systemd-bootx64.efi
    }
  '';

  boot = {
    extraModulePackages = [
      config.boot.kernelPackages.evdi
    ];
    kernelPackages = pkgs.linuxPackages_zen;
  };
}
