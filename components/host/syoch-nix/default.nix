{
  config,
  pkgs,
  ...
}:
{
  system.stateVersion = "25.11";

  imports = [
    ./hardware-configuration.nix
    ./secrets.nix
    ./de.nix
    ./wifi.nix
  ];

  # Drives
  fileSystems."/mnt/windows" = {
    device = "/dev/disk/by-uuid/EC6A27026A26C962";
    options = [ "nofail" ];
  };
  fileSystems."/mnt/usbssd" = {
    device = "/dev/disk/by-uuid/26E8A3ACE8A378A7";
    options = [ "nofail" ];
  };

  boot.extraModulePackages = [
    config.boot.kernelPackages.evdi
  ];

  nixpkgs.config.allowUnfree = true;

  # config
  os-mod.system.enable = true;
  os-mod.system.allowWheelToRunSudo = true;

  os-mod.user-syoch.enable = true;
  os-mod.sshd.enable = true;
  os-mod.pipewire.enable = true;
  os-mod.i18n-jp.enable = true;
  os-mod.bluetooth.enable = true;
  os-mod.libvirtd.enable = true;
  os-mod.tailscale.enable = true;

  programs.vim.enable = true;
  programs.htop.enable = true;
  programs.wireshark.enable = true;
  programs.git.enable = true;

  services.libinput.enable = true;
  services.upower.enable = true;
  services.flatpak.enable = true;
  services.twingate.enable = true;

  virtualisation.docker.enable = true;

  networking.hostName = "syoch-nix";
  networking.networkmanager.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  environment.systemPackages = with pkgs; [
    wget
    jq
    ruff
    python314
    gnumake
    ghq
    binwalk
    nixfmt-rfc-style
    brightnessctl
    hexyl
    neofetch
    ddcutil
    netdiscover
    displaylink
    socat
    file
    ffmpeg
    github-desktop
    keepassxc
  ];
}
