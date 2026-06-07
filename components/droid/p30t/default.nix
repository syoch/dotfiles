{
  config,
  pkgs,
  ...
}:
{
  system.stateVersion = "24.05";

  imports = [
    ./services.nix
    ./shell.nix
    ./sshd.nix
  ];

  services.enable = true;

  environment.packages = [
    pkgs.openssh
    pkgs.git
    pkgs.wget
    pkgs.neovim
    pkgs.ps
    pkgs.syncthing
    pkgs.p7zip
    pkgs.file
    pkgs.clang
    pkgs.gnumake
  ];

  shell.enable = true;
  services.executables.syncthing = "${pkgs.syncthing}/bin/syncthing";

  terminal.font = "${config.user.home}/dotfiles/Assets/Firple-Regular.ttf";

  environment.etcBackupExtension = ".bak";

  nix.package = pkgs.nix;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  home-manager = {
    config = {
      imports = [
        ./home.nix
        ../../../modules-hm/cui
        ../../../modules-hm/services
      ];
    };
    backupFileExtension = "hm-bak";
    useGlobalPkgs = true;
  };

  time.timeZone = "Asia/Tokyo";
}
