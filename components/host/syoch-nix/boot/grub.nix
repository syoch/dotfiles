{
  boot.loader.grub.device = "nodev";
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.enable = true;
  boot.loader.grub.extraEntries = ''
    menuentry "Chainloading to systemd-boot" {
    	chainloader /EFI/systemd/systemd-bootx64.efi
    }
  '';
}
