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

    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";

    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
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
      nixos-generators,
      nix-on-droid,
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
      nixOnDroidConfigurations.default = nix-on-droid.lib.nixOnDroidConfiguration {
        modules = [
          ./nix-on-droid.nix
        ];

        extraSpecialArgs = {
        };
        pkgs = import nixpkgs {
          system = "aarch64-linux";

          overlays = [
            nix-on-droid.overlays.default
          ];
        };

        home-manager-path = home-manager.outPath;
      };
      packages.x86_64-linux.iso = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "iso";
        specialArgs = {
          inherit inputs;
        };
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          ./components/host/rescue
          {
            system.stateVersion = "23.11";
          }
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
