{
  description = "ssolo flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        sokol-shdc = pkgs.stdenv.mkDerivation {
          name = "sokol-shdc";
          version = "unstable";

          src = pkgs.fetchurl {
            url =
              "https://github.com/floooh/sokol-tools-bin/raw/master/bin/linux/sokol-shdc";
            sha256 = "1qpm8rp1dgidllq563njwrjrg1w2nk9j4akvjc0qhjhxqj60pi8x";
          };

          dontUnpack = true;

          installPhase = ''
            mkdir -p $out/bin
            cp $src $out/bin/sokol-shdc
            chmod +x $out/bin/sokol-shdc
          '';
        };

        buildInputs = with pkgs; [
          zig
          sokol-shdc
          xorg.libX11
          xorg.libXi
          xorg.libXcursor
          libGL
          alsa-lib
        ];
      in {
        packages.default = pkgs.stdenv.mkDerivation {
          name = "ssolo";
          src = ./.;

          nativeBuildInputs = buildInputs;

          buildPhase = ''
            zig build -Doptimize=ReleaseSafe
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp zig-out/bin/* $out/bin/
          '';
        };

        devShells.default = pkgs.mkShell { inherit buildInputs; };
      });
}
