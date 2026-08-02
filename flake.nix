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
      baseFacts = {
        userName = "makifun";
        domainName = "makifun.se";
        timeZone = "Europe/Stockholm";
      };
      hosts = {
        lan = "10.10.10.0/24";
        wireguard = "10.10.11.0/24";
        opnsense = "10.10.10.1";
        technitium = "10.10.10.3";
        storma = "10.10.10.12";
        ligma = "10.10.10.13";
        bofa = "10.10.10.14";
        playma = "10.10.10.15";
        arrma = "10.10.10.16";
        sugma01 = "10.10.10.26";
        sugma02 = "10.10.10.27";
        sugma03 = "10.10.10.28";
        sugmaVIP = "10.10.10.29";
        sugmaGW = "10.10.10.30";
      };
      mkSystem =
        modules:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit baseFacts hosts; };
          modules = defaultModules ++ modules;
        };
    in
    {
      nixosConfigurations = {
        arrma = mkSystem [ ./hosts/arrma ];
        bofa = mkSystem [ ./hosts/bofa ];
        ligma = mkSystem [ ./hosts/ligma ];
        playma = mkSystem [ ./hosts/playma ];
        storma = mkSystem [ ./hosts/storma ];
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
