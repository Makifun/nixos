{ config, ... }:
{
  sops.secrets.nixos-github-pull-token = {
    sopsFile = ./secrets.yaml;
  };

  sops.templates."nix-access-tokens.conf" = {
    content = ''
      access-tokens = github.com=${config.sops.placeholder."nixos-github-pull-token"}
    '';
    # Readable by nix CLI (user) for flake fetches; token is read-only so 0444 is safe.
    mode = "0444";
  };

  nix.extraOptions = ''
    !include ${config.sops.templates."nix-access-tokens.conf".path}
  '';
}
