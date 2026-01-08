{ pkgs, ... }:

{
  system.stateVersion = "25.11";

  imports = [
    ./hardware-configuration.nix
    ./secrets.nix
    ./vpn.nix
  ];

  # Config
  os-mod.system.enable = true;
  os-mod.system.allowWheelToRunSudo = true;

  os-mod.user-syoch.enable = true;

  os-mod.tailscale.enable = true;
  os-mod.sshd.enable = true;

  programs.tmux.enable = true;

  networking.hostName = "syoch-sv01";
  networking.networkmanager.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  os-mod.router = {
    enable = true;
    upstream.interface = "enp0s31f6";
    downstream.interface = "enp0s20f0u4u4i5";
    downstream.ipAddress = "10.42.0.1";
    downstream.prefixLength = 16;
    downstream.dhcpRangeStart = "10.42.100.0";
    downstream.dhcpRangeEnd = "10.42.200.0";
  };

  environment.systemPackages = with pkgs; [
    neovim
    wget
  ];
}
