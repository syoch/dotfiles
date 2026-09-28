{
  config,
  pkgs,
  ...
}:
{
  system.stateVersion = "24.05";

  imports = [
    ./services.nix
    ./sshd.nix
  ];

  services.enable = true;

  environment.packages = [
    pkgs.openssh
    pkgs.coreutils
    pkgs.bashInteractive
  ];

  environment.etcBackupExtension = ".bak";

  nix.package = pkgs.nix;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  time.timeZone = "Asia/Tokyo";
}
