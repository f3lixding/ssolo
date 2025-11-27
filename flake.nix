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
        # Can't do this for now. The Zig build system would try to do the following, which are forbidden by the nix sandbox:
        # - Download packages from build.zig.zon (no network access)
        # - Write it to global zig cache (no access to such a dir)
        # In order for this to work properly, we would need to prefetch dependencies.
        # There are tools out there that does this (e.g. zig2nix). But I haven't figured out how to handle transitive dependency with it yet.
        #
        # That is with the exception of disabling sandbox i.e. nix build --option sandbox false
        # though you do need privlege escalation so you would need to run it iwth sudo i.e. sudo nix build --option sandbox false
        packages.default = pkgs.stdenv.mkDerivation {
          name = "ssolo";
          src = ./.;

          nativeBuildInputs = buildInputs;

          preBuild = ''
            export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
          '';

          buildPhase = ''
            runHook preBuild
            zig build -Doptimize=ReleaseSafe
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            cp zig-out/bin/* $out/bin/
            runHook postInstall
          '';
        };

        devShells.default = pkgs.mkShell {
          inherit buildInputs;

          shellHook = ''
            exec ${pkgs.zsh}/bin/zsh
          '';
        };
      });
}
