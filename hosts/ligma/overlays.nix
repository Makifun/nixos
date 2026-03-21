{ lib, ... }:
{
  nixpkgs.overlays = [
    (final: prev: {
      fosrl-pangolin = prev.fosrl-pangolin.overrideAttrs {
        version = "1.16.2";
        src = prev.fetchFromGitHub {
          owner = "fosrl";
          repo = "pangolin";
          tag = "1.16.2";
          hash = "sha256-pWD2VinfkCiSSP6/einXgduKQ8lzWdHlrj2eqUU/x6Y=";
        };
        npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
    })
  ];
}
