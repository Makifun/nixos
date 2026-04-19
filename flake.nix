{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    impermanence.url = "github:nix-community/impermanence";
    sops-nix.url = "github:Mic92/sops-nix";
    authentik-nix.url = "github:nix-community/authentik-nix/8048437d601f772be45e10495d975cf0ac4acbf7";
  };

  outputs =
    {
      nixpkgs,
      disko,
      impermanence,
      sops-nix,
      authentik-nix,
      ...
    }:
    let
      system = "x86_64-linux";
      defaultModules = [
        disko.nixosModules.disko
        impermanence.nixosModules.impermanence
        sops-nix.nixosModules.sops
        authentik-nix.nixosModules.default
      ];
    in
    {
      nixosConfigurations = {
        ligma = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = defaultModules ++ [
            ./hosts/ligma
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
