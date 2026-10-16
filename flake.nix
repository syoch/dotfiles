{

  description = "NixOS Configuration by syoch";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-2511.url = "github:nixos/nixpkgs/nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager-2511 = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs-2511";
    };
    astal.url = "github:aylur/astal";
    ags.url = "github:aylur/ags";

    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";

    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs-2511";
      inputs.home-manager.follows = "home-manager-2511";
    };
  };

  inputs.sops-nix.url = "github:Mic92/sops-nix";
  inputs.sops-nix.inputs.nixpkgs.follows = "nixpkgs";

  inputs.syoch-infra.url = "github:syoch/infrastructure";

  inputs.vscode-server.url = "github:nix-community/nixos-vscode-server";

  outputs =
    {
      nixpkgs,
      nixpkgs-unstable,
      nixpkgs-2511,
      home-manager,
      home-manager-2511,
      sops-nix,
      ags,
      nixos-generators,
      nix-on-droid,
      syoch-infra,
      vscode-server,
      ...
    }@inputs:
    let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [
          (final: prev: {
            unstable = import nixpkgs-unstable {
              inherit (final) system;
            };
          })
        ];
      };
      homeManagerModules = [
        ./modules-hm
        ags.homeManagerModules.default
      ];
      nixosSystem =
        folder: extraModules:
        nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs;
            components = ./components;
          };
          system = "x86_64-linux";
          modules = [
            ./modules-nixos
            ./components/host/${folder}
            sops-nix.nixosModules.sops
            syoch-infra.nixosModules.portal
          ]
          ++ extraModules;
        };
    in
    {
      nixosConfigurations.sv01 = nixosSystem "sv01" [
      ];
      nixosConfigurations.laptop = nixosSystem "syoch-nix" [
        vscode-server.nixosModules.default
        (
          { config, pkgs, ... }:
          {
            services.vscode-server.enable = true;
          }
        )
      ];

      nixOnDroidConfigurations.default = nix-on-droid.lib.nixOnDroidConfiguration {
        pkgs = import nixpkgs-2511 { system = "aarch64-linux"; };
        modules = [
          ./components/droid/p30t
          {
            environment.packages = [
              syoch-infra.packages.aarch64-linux.portal-device-agent
            ];
          }
        ];

        home-manager-path = home-manager-2511.outPath;
      };

      # Minimal configuration for initial bootstrap (sshd only).
      # Used to bring up SSH access on a fresh phone, before deploying the full p30t config.
      nixOnDroidConfigurations.initial = nix-on-droid.lib.nixOnDroidConfiguration {
        pkgs = import nixpkgs-2511 { system = "aarch64-linux"; };
        modules = [
          ./components/droid/initial
        ];
        home-manager-path = home-manager-2511.outPath;
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
        inherit pkgs;
        extraSpecialArgs = {
          inherit inputs;
        };
        modules = homeManagerModules ++ [ ./components/home/syoch ];
      };
      devShells.x86_64-linux.default = pkgs.mkShell {
        packages = [
          pkgs.amdctl
          pkgs.nix-output-monitor
          pkgs.home-manager
          pkgs.nix-tree
          pkgs.nix-du
          pkgs.ncdu
          pkgs.unzip
          pkgs.wireshark
          pkgs.bun
          pkgs.android-tools
          pkgs.scrcpy
          pkgs.apache-directory-studio
          nix-on-droid.packages.x86_64-linux.nix-on-droid
        ];
      };
    };

}
