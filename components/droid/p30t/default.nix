{
  pkgs,
  ...
}:
{
  system.stateVersion = "24.05";

  environment.packages = [
    pkgs.neovim
    pkgs.hostname
    pkgs.zsh
  ];
  user.shell = "${pkgs.zsh}/bin/zsh";

  environment.etcBackupExtension = ".bak";
  services.sshd.enable = true;

  nix.package = pkgs.nix;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  time.timeZone = "Asia/Tokyo";
}
