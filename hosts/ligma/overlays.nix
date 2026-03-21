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
        fosrl-pangolin = prev.fosrl-pangolin.overrideAttrs (old: {
          version = "1.16.2";
          src = newSrc;
          npmDeps = prev.fetchNpmDeps {
            src = newSrc;
            hash = "sha256-CwS26eRAIuxJ2fekRRapDWYAOHXPV0mIX/by4uW2ZOM=";
          };
          postPatch = ''
            substituteInPlace src/app/layout.tsx --replace-fail \
              "{ Inter } from \"next/font/google\"" \
              "localFont from \"next/font/local\""

            substituteInPlace src/app/layout.tsx --replace-fail \
              "const inter = Inter({${ "\n"}    subsets: [\"latin\"]${ "\n"}});${ "\n"}${ "\n"}const fontClassName = inter.className;" \
              "const fontClassName = localFont({ src: './Inter.ttf' }).className;"

            cp "${prev.inter}/share/fonts/truetype/InterVariable.ttf" src/app/Inter.ttf
          '';
        });
      })
  ];
}
