{ pkgs, config, ... }:
{
  system.stateVersion = "25.11";

  imports = [
    ./hardware-configuration.nix
    ./hardware-specific.nix
    ./secrets.nix
    ./de.nix
    ./wifi.nix
    ./vm-lab.nix
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

  services.resolved.enable = false;

  sops.secrets."netbird-wt0-setup-key" = {
    owner = "root";
    path = "/etc/nixos/netbird-wt0-setup-key";
  };
  services.netbird.clients.wt0 = {
    login = {
      enable = true;
      setupKeyFile = config.sops.secrets."netbird-wt0-setup-key".path;
    };
    port = 51821;
    ui.enable = false;
    dns-resolver.address = "127.0.0.53";
    dns-resolver.port = 5053;
    openFirewall = true;
    openInternalFirewall = true;
  };

  services.dnsmasq = {
    enable = true;
    settings.interface = "lo";
    settings.listen-address = "127.0.0.1";
    servers = [
      "/nnctrobo.internal/127.0.0.53#5053"
      "/syoch.internal/10.42.0.1"
      "1.1.1.1"
      "1.0.0.1"
    ];
  };
  networking.nameservers = [ "127.0.0.1" ];

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
    wshowkeys
  ];
}
