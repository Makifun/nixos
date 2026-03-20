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
      defaultModules = [
        disko.nixosModules.disko
        impermanence.nixosModules.impermanence
        sops-nix.nixosModules.sops
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
            ./common
          ];
        };
      };

      devShells.${system}.default =
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          sandbox =
            import (fetchTarball "https://github.com/archie-judd/agent-sandbox.nix/archive/main.tar.gz")
              {
                inherit pkgs;
              };
          claude-sandboxed = sandbox.mkSandbox {
            pkg = pkgs.claude-code;
            binName = "claude";
            outName = "claude-sandboxed";
            allowedPackages = with pkgs; [
              coreutils
              which
              bash
              git
              ripgrep
              fd
              gnused
              gnugrep
              findutils
              jq
            ];
            stateDirs = [ "$HOME/.claude" ];
            stateFiles = [
              "$HOME/.claude.json"
              "$HOME/.claude.json.lock"
            ];
            extraEnv = {
              CLAUDE_CODE_OAUTH_TOKEN = "$CLAUDE_CODE_OAUTH_TOKEN";
              GITHUB_TOKEN = "$GITHUB_TOKEN";
              GIT_AUTHOR_NAME = "claude-agent";
              GIT_AUTHOR_EMAIL = "claude-agent@localhost";
              GIT_COMMITTER_NAME = "claude-agent";
              GIT_COMMITTER_EMAIL = "claude-agent@localhost";
            };
            restrictNetwork = true;
            allowedDomains = [
              "anthropic.com"
              "api.anthropic.com"
              "claude.com"
              "raw.githubusercontent.com"
              "api.github.com"
            ];
          };
        in
        pkgs.mkShell { packages = [ claude-sandboxed ]; };
    };
}
