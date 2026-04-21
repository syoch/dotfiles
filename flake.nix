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
      packages.x86_64-linux.a2ln-server =
        let
          project = pyproject-nix.lib.project.loadPyproject {
            projectRoot = pkgs.fetchFromGitHub {
              owner = "patri9ck";
              repo = "a2ln-server";
              rev = "72635e644d509820424466bf1520b4b4e6730b0d";
              sha256 = "sha256-5IrjegEHxd33fxJHumpWi9zXViEl2CmcGsCJdJlXCaA=";
            };
          };
          python = pkgs.python3;
          a = pyproject-nix.lib.renderers.buildPythonPackage { inherit project python; };
        in
        a;
      packages.x86_64-linux.adb_re = import ./__________/adb_re {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
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
            nix-tree
            nix-du
            ncdu
            unzip
            ipmitool
            wireshark-qt
          ];
        };
    };

}
