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

    # UEFI
    boot.loader.efi.efiSysMountPoint = "/boot/efi";
    boot.loader.efi.canTouchEfiVariables = true;
    boot.loader.grub.device = lib.mkDefault "nodev";
    boot.loader.grub.efiSupport = true;
    boot.loader.grub.enable = true;

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
    nix.settings.extra-sandbox-paths = [
      "/nix/var/cache/ccache"
    ];
  };
}
