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
    ./bluetooth.nix
    ./de.nix
    ./hardware-configuration.nix
    ./networking.nix
    ./security.nix
  ];

  os-mod.sshd.enable = true;
  os-mod.gnupg.enable = true;
  os-mod.pipewire.enable = true;
  os-mod.i18n-jp.enable = true;

  # RF modules
  os-mod.bluetooth.enable = true;

  # virtualisation
  os-mod.libvirtd.enable = true;
  virtualisation.docker.enable = true;

  sops.defaultSopsFile = ../../../secrets.yaml;
  sops.age.sshKeyPaths = [
    "/home/syoch/.config/sops/age/id_syoch"
  ];
  sops.secrets."ssh-config" = {
    owner = "syoch";
    path = "/home/syoch/.ssh/config.d/secret";
  };

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
  programs.nix-index.enable = true;
  programs.nix-index.enableZshIntegration = true;
  programs.wireshark.enable = true;
  services.upower.enable = true;
  services.flatpak.enable = true;

  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    openssl_1_1
    gobject-introspection
    nss
    nspr
  ];
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
    nixd
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
