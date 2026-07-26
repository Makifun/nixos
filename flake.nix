{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    impermanence.url = "github:nix-community/impermanence";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs =
    {
      nixpkgs,
      disko,
      impermanence,
      sops-nix,
      ...
    }:
    let
      system = "x86_64-linux";
      defaultModules = [
        disko.nixosModules.disko
        impermanence.nixosModules.impermanence
        sops-nix.nixosModules.sops
      ];
      hosts = {
        ligma = "10.10.10.13";
        storma = "10.10.10.12";
        bofa = "10.10.10.14";
        playma = "10.10.10.15";
        jonny = "10.10.10.16";
        opnsense = "10.10.10.1";
        technitium = "10.10.10.3";
        sugma01 = "10.10.10.26";
        sugma02 = "10.10.10.27";
        sugma03 = "10.10.10.28";
        sugmaVip = "10.10.10.29";
        sugmaGateway = "10.10.10.30";
      };
    in
    {
      nixosConfigurations = {
        ligma = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit hosts; };
          modules = defaultModules ++ [
            ./hosts/ligma
          ];
        };
        bofa = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit hosts; };
          modules = defaultModules ++ [
            ./hosts/bofa
          ];
        };
        storma = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit hosts; };
          modules = defaultModules ++ [
            ./hosts/storma
          ];
        };
        playma = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit hosts; };
          modules = defaultModules ++ [
            ./hosts/playma
          ];
        };
        minimaliso = nixpkgs.lib.nixosSystem {
          inherit system;
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
            ./common/users.nix
          ];
        };
      };
    };
}
