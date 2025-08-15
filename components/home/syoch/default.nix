{
  nixgl,
  config,
  inputs,
  pkgs,
  ...
}:
{
  home.username = "syoch";
  home.homeDirectory = "/home/syoch";
  home.stateVersion = "25.05";

  imports = [
    inputs.ags.homeManagerModules.default
    ./audio.nix
    ./tools.nix
    ./cui.nix
    ./winapps.nix
    ./de
  ];

  home.packages = with pkgs; [
    dotnet-sdk_9
    prismlauncher
    clang-tools
    wineWowPackages.stableFull
    kicad
  ];

  programs = {
    direnv = {
      enable = true;
      enableZshIntegration = true; # see note on other shells below
      nix-direnv.enable = true;
    };
  };

  home.file.".local/share/PrismLauncher/instances".source =
    config.lib.file.mkOutOfStoreSymlink "/mnt/usbssd/NAS/Apps/_Game/PolyMC-Windows-Portable-1.4.3/instances";

  nixGL.packages = import nixgl { inherit pkgs; };
  nixGL.defaultWrapper = "mesa"; # or whatever wrapper you need
  nixGL.installScripts = [ "mesa" ];

  nixpkgs.config.allowUnfree = true;

  programs.home-manager.enable = true;
}
