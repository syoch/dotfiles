{ pkgs, ... }:
{
  system.stateVersion = "25.11";

  imports = [
    ./hardware-configuration.nix
    ./hardware-specific.nix
    ./secrets.nix
    ./de.nix
    ./wifi.nix
    # ./vm-lab.nix
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

  nix.settings.extra-sandbox-paths = [
    "/nix/var/cache/ccache"
  ];

  services.cloudflared.enable = true;

  nixpkgs.config.permittedInsecurePackages = [
    "openssl-1.1.1w"
  ];

  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    openssl_1_1
    gobject-introspection
    nss
    nspr
  ];

  services.udev.extraRules = ''
    SUBSYSTEMS=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="374b", MODE="0666"
  '';

  nix.settings.substituters = [
    "https://nnctrobo.cachix.org"
  ];
  nix.settings.trusted-public-keys = [
    "nnctrobo.cachix.org-1:1dKKIMpU2HT8hYTQVOxaE8YGT1rVvHpZNjgkMCrIRzM="
  ];

  programs.steam = {
    enable = true;
  };

  environment.systemPackages = with pkgs; [
    wget
    jq
    ruff
    python314
    gnumake
    ghq
    binwalk
    nixfmt
    brightnessctl
    hexyl
    fastfetch
    ddcutil
    netdiscover
    displaylink
    socat
    file
    ffmpeg
    github-desktop
    keepassxc
    cifs-utils
  ];
}
