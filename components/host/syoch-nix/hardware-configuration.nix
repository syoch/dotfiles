{
  config,
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "uas"
  ];
  boot.initrd.kernelModules = [ "dm-snapshot" ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/6aa493c5-ee38-4f9a-adbf-944168b48219";
    fsType = "ext4";
  };

  fileSystems."/mnt/data" = {
    device = "/dev/lvg-share/data";
    options = [ "nofail" ];
  };

  fileSystems."/mnt/windows" = {
    device = "/dev/disk/by-uuid/EC6A27026A26C962";
  };

  fileSystems."/var/lib/docker" = {
    device = "/dev/lvg-share/docker";
    fsType = "ext4";
    options = [ "nofail" ];
  };

  fileSystems."/mnt/usbssd" = {
    device = "/dev/disk/by-uuid/26E8A3ACE8A378A7";
    fsType = "ntfs";
    options = [ "nofail" ];
  };

  swapDevices = [
    { device = "/dev/disk/by-uuid/bcdb0ace-67c7-489f-a2f7-9eac47bb7067"; }
  ];

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
