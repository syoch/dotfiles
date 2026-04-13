{ config, ... }:
{
  # Drives
  fileSystems."/mnt/windows" = {
    device = "/dev/disk/by-uuid/EC6A27026A26C962";
    fsType = "ntfs3";
    options = [ "nofail" ];
  };
  fileSystems."/mnt/usbssd" = {
    device = "/dev/disk/by-uuid/26E8A3ACE8A378A7";
    fsType = "ntfs3";
    options = [ "nofail" ];
  };

  boot.extraModulePackages = [
    config.boot.kernelPackages.evdi
  ];
  boot.supportedFilesystems = [
    "nfs"
    "ntfs"
  ];

  os-mod.nfs-client.enable = true;
  os-mod.nfs-client.mounts."/mnt/NAS" = {
    what = "100.96.100.1:/srv/NAS";
    options = [ "noatime" ];
  };
}
