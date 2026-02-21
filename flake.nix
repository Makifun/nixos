{
inputs = {
  nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
  disko.url = "github:nix-community/disko";
  disko.inputs.nixpkgs.follows = "nixpkgs";
  impermanence.url = "github:nix-community/impermanence";
};

outputs = { self, nixpkgs, disko, impermanence, ... }: 
  let system = "x86_64-linux"; in
  {
    nixosConfigurations = {
      ligma = nixpkgs.lib.nixosSystem {
        system = system;
        modules = [
          disko.nixosModules.disko
          impermanence.nixosModules.impermanence
          ./common/users.nix
          ./hosts/ligma/disko-config.nix
          ./hosts/ligma/configuration.nix
        ];
      };
      minimaliso = nixpkgs.lib.nixosSystem {
        system = system;
        modules = [
          ({ pkgs, modulesPath, ... }: {
            imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];
            isoImage.squashfsCompression = "gzip -Xcompression-level 1";
          })
          ./common/users.nix
        ];
      };
    };
  };
}