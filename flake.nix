{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    impermanence.url = "github:nix-community/impermanence";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      disko,
      impermanence,
      sops-nix,
      ...
    }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations = {
        ligma = nixpkgs.lib.nixosSystem {
          system = system;
          modules = [
            disko.nixosModules.disko
            impermanence.nixosModules.impermanence
            sops-nix.nixosModules.sops
            ./hosts/ligma
          ];
        };
        minimaliso = nixpkgs.lib.nixosSystem {
          system = system;
          modules = [
            (
              {
                pkgs,
                modulesPath,
                lib,
                ...
              }:
              {
                imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];
                image.baseName = lib.mkForce "nixos-minimal-${system}";
              }
            )
            ./common
          ];
        };
      };
    };
}
