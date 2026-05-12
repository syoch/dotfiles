{
  pkgs,
  ...
}:
{
  system.stateVersion = "24.05";

  environment.packages = with pkgs; [
    neovim
    hostname
  ];

  environment.etcBackupExtension = ".bak";

  nix.package = pkgs.nix;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  time.timeZone = "Asia/Tokyo";
}
