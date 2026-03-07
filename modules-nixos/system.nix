{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.os-mod.system;
in
{
  options.os-mod.system = {
    enable = lib.mkEnableOption "system configuration";
    bootMode = lib.mkOption {
      type = lib.types.enum [
        "uefi"
        "bios"
      ];
      default = "uefi";
      description = "Enable UEFI or BIOS boot mode.";
    };
    bootDevice = lib.mkOption {
      type = lib.types.str;
      default = "nodev";
      description = "The device to install the MBR bootloader to ('nodev' for uefi systems)";
    };
    allowWheelToRunSudo = lib.mkEnableOption "allow users in wheel group to run sudo";
  };

  config = lib.mkIf cfg.enable {
    # Linux
    boot.kernelPackages = pkgs.linuxPackages_zen;
    security.rtkit.enable = true;
    security.sudo.extraRules = lib.mkIf cfg.allowWheelToRunSudo [
      {
        commands = [ ];
        groups = [ "wheel" ];
      }
    ];

    # UEFI/BIOS
    boot.loader.efi = lib.mkIf (cfg.bootMode == "uefi") {
      efiSysMountPoint = "/boot/efi";
      canTouchEfiVariables = true;
    };
    boot.loader.grub.device = cfg.bootDevice;
    boot.loader.grub.efiSupport = (cfg.bootMode == "uefi");
    boot.loader.grub.enable = true;
    boot.loader.grub.useOSProber = true;

    # Swap
    zramSwap.enable = true;
    boot.kernel.sysctl."vm.swappiness" = 5;

    # Nix
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    nix.settings.trusted-users = [
      "root"
      "syoch"
      "@wheel"
    ];
  };
}
