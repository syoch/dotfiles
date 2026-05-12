{

  description = "NixOS Configuration by syoch";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-2405.url = "github:nixos/nixpkgs/nixos-24.05";
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
    pyproject-nix = {
      url = "github:nix-community/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  inputs.sops-nix.url = "github:Mic92/sops-nix";
  inputs.sops-nix.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    {
      nixpkgs,
      nixpkgs-2405,
      home-manager,
      sops-nix,
      nixgl,
      ags,
      nixos-generators,
      nix-on-droid,
      pyproject-nix,
      ...
    }@inputs:
    let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
      };
      homeManagerModules = [
        ./modules-hm
        ags.homeManagerModules.default
      ];
      nixosSystem =
        folder:
        nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs;
            inherit nixgl;
            components = ./components;
          };
          system = "x86_64-linux";
          modules = [
            ./modules-nixos
            ./components/host/${folder}
            sops-nix.nixosModules.sops
          ];
        };
    in
    {
      nixosConfigurations.sv01 = nixosSystem "sv01";
      nixosConfigurations.syoch-nix = nixosSystem "syoch-nix";

      nixOnDroidConfigurations.default = nix-on-droid.lib.nixOnDroidConfiguration {
        modules = [
          ./components/droid/p30t
          {
            home-manager = {
              config = ./components/home/syoch-p30t.nix;
              backupFileExtension = "hm-bak";
              useGlobalPkgs = true;
              sharedModules = homeManagerModules;
            };
          }
        ];

        extraSpecialArgs = { };
        pkgs = import nixpkgs {
          system = "aarch64-linux";

          overlays = [ nix-on-droid.overlays.default ];
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
        };
        modules = homeManagerModules // [ ./components/home/syoch ];
      };
      devShells.x86_64-linux.default = pkgs.mkShell {
        packages = with pkgs; [
          amdctl
          nix-output-monitor
          pkgs.home-manager
          nix-tree
          nix-du
          ncdu
          unzip
          wireshark-qt

          pkgs.android-tools
          pkgs.scrcpy
        ];
      };
    };

}
