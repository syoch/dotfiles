{
  lib,
  pkgs,
  ...
}:
# nix build .#iso
# sudo dd bs=4M if=result/iso/syoch-rescue-iso.iso of=/dev/sdX status=progress oflag=sync
{
  networking.hostName = "rescue-iso";
  networking.networkmanager.enable = true;

  boot.supportedFilesystems = [
    "zfs"
    "f2fs"
  ];

  users.mutableUsers = false;

  # Turn on flakes.
  nix.package = pkgs.nixVersions.stable;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  environment.etc.nixcfg.source = builtins.filterSource (
    path: type:
    baseNameOf path != ".git"
    && type != "symlink"
    && !(pkgs.lib.hasSuffix ".qcow2" path)
    && baseNameOf path != "secrets"
  ) ../.;

  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    htop
    tmux
    tree
    nano
    neovim
    rsync
    testdisk
  ];

  # Part of base-system.nix:
  time.timeZone = lib.mkDefault "Asia/Tokyo";

  i18n = {
    defaultLocale = "ja_JP.UTF-8";
    extraLocaleSettings = {
      LC_TIME = "ja_JP.UTF-8";
    };
    supportedLocales = lib.mkDefault [
      "ja_JP.UTF-8/UTF-8"
      "en_US.UTF-8/UTF-8"
    ];
  };
  environment.variables = {
    TERM = "xterm-256color";
  };

  # # Use a high-res font.
  console = {
    earlySetup = true;
    font = "Lat2-Terminus16";
    useXkbConfig = true;
  };

  image.fileName = lib.mkForce "syoch-rescue-iso.iso";
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";
}
