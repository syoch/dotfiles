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
      ...
    }@inputs:
    {
      nixosConfigurations.syoch-nix = nixpkgs.lib.nixosSystem rec {
        specialArgs = {
          inherit inputs;
          inherit nixgl;
          components = ./components;
        };
        system = "x86_64-linux";
        modules = [
          ./components/host/syoch-nix
          sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = specialArgs;
            home-manager.backupFileExtension = "old";
            home-manager.users.syoch = import ./components/home/syoch;
          }
        ];
      };
    };

}
