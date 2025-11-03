{
  pkgs,
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.os-mod.libvirtd;
in
{
  options.os-mod.libvirtd = {
    enable = mkEnableOption "libvirtd";
  };

  config = mkIf cfg.enable {
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true;
      };
    };
    networking.firewall.trustedInterfaces = [ "virbr0" ];
    virtualisation.spiceUSBRedirection.enable = true;

    programs.virt-manager.enable = true;

  };
}
