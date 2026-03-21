{ ... }:
{
  nixpkgs.overlays = [
    (final: prev:
      let
        newSrc = prev.fetchFromGitHub {
          owner = "fosrl";
          repo = "pangolin";
          tag = "1.16.2";
          hash = "sha256-pWD2VinfkCiSSP6/einXgduKQ8lzWdHlrj2eqUU/x6Y=";
        };
      in {
        fosrl-pangolin = prev.fosrl-pangolin.overrideAttrs {
          version = "1.16.2";
          src = newSrc;
          npmDeps = prev.fetchNpmDeps {
            src = newSrc;
            hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
          };
        };
      })
  ];
}
