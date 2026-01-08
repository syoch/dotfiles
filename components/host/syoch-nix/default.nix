{
  components,
  pkgs,
  ...
}:
{
  system.stateVersion = "25.11";

  imports = [
    ./boot
    (components + "/user/syoch")
    ./de.nix
    ./hardware-configuration.nix
    ./networking.nix
    ./security.nix
  ];

  # sops
  sops.defaultSopsFile = ../../../secrets.yaml;
  sops.age.sshKeyPaths = [
    "/home/syoch/.config/sops/age/id_syoch"
  ];
  sops.secrets."ssh-config" = {
    owner = "syoch";
    path = "/home/syoch/.ssh/config.d/secret";
  };

  # Drives
  fileSystems."/mnt/windows" = {
    device = "/dev/disk/by-uuid/EC6A27026A26C962";
    options = [ "nofail" ];
  };
  fileSystems."/mnt/usbssd" = {
    device = "/dev/disk/by-uuid/26E8A3ACE8A378A7";
    options = [ "nofail" ];
  };
  zramSwap.enable = true;
  boot.kernel.sysctl."vm.swappiness" = 5;

  # config
  os-mod.sshd.enable = true;
  os-mod.pipewire.enable = true;
  os-mod.i18n-jp.enable = true;
  nix.settings.extra-sandbox-paths = [
    "/nix/var/cache/ccache"
  ];

  # RF modules
  os-mod.bluetooth.enable = true;

  # virtualisation
  os-mod.libvirtd.enable = true;
  virtualisation.docker.enable = true;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.permittedInsecurePackages = [
    "openssl-1.1.1w"
  ];

  programs.zsh.enable = true;
  services.libinput.enable = true;
  programs.vim.enable = true;
  programs.htop.enable = true;
  programs.wireshark.enable = true;
  services.upower.enable = true;
  services.flatpak.enable = true;

  programs.git.enable = true;
  environment.systemPackages = with pkgs; [
    wget
    pciutils
    jq
    ruff
    python314
    gnumake
    ghq
    binwalk
    hyprlang
    hyprls
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
    # kicad
    github-desktop
    keepassxc
  ];
}
