{
  components,
  pkgs,
  ...
}:
{
  imports = [
    ./boot
    (components + "/service/gpg-agent")
    (components + "/service/sshd")
    (components + "/service/tailscale")
    (components + "/user/syoch")
    ./bluetooth.nix
    ./audio.nix
    ./de.nix
    ./hardware-configuration.nix
    ./i18n.nix
    ./networking.nix
    ./security.nix
    ./virtualisation.nix
    # ./k9s.nix
  ];

  sops.defaultSopsFile = ../../../secrets.yaml;
  sops.age.sshKeyPaths = [
    "/home/syoch/.config/sops/age/id_syoch"
  ];
  sops.secrets."ssh-config" = {
    owner = "syoch";
    path = "/home/syoch/.ssh/config.d/secret";
  };

  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  services.libinput.enable = true;

  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;

  environment.systemPackages = with pkgs; [
    # Essential tools
    vim
    wget
    git

    htop
    pciutils

    gcc
    gdb
    nodejs

    jq
    wireshark
    ruff

    nix-index

    python313Full
    nix-output-monitor
    chromium

    gnumake
  ];

  programs.nix-ld.enable = true;

  nixpkgs.config.permittedInsecurePackages = [
    "openssl-1.1.1w"
  ];
  programs.nix-ld.libraries = with pkgs; [
    openssl_1_1
    gobject-introspection
    nss
    nspr
  ];

  networking.firewall.trustedInterfaces = [ "virbr0" ];

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "25.11"; # Did you read the comment?
}
