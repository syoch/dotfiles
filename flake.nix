{

  description = "NixOS Configuration by syoch";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    astal.url = "github:aylur/astal";
    ags.url = "github:aylur/ags";
    winapps.url = "github:winapps-org/winapps";
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  inputs.sops-nix.url = "github:Mic92/sops-nix";
  inputs.sops-nix.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    {
      nixpkgs,
      home-manager,
      sops-nix,
      nixgl,
      ags,
      ...
    }@inputs:
    {
      nixosConfigurations.syoch-nix = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs;
          inherit nixgl;
          components = ./components;
        };
        system = "x86_64-linux";
        modules = [
          ./modules-nixos

          ./components/host/syoch-nix

          sops-nix.nixosModules.sops
        ];
      };
      homeConfigurations."syoch" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        extraSpecialArgs = {
          inherit inputs;
          inherit nixgl;
          components = ./components;
        };
        modules = [
          ./modules-hm

          ags.homeManagerModules.default
          ./components/home/syoch
        ];
      };
      devShells.x86_64-linux.default =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
        in
        pkgs.mkShell {
          packages = with pkgs; [
            pnpm
            amdctl
            nix-output-monitor
            pkgs.home-manager
          ];
        };
    };

}
