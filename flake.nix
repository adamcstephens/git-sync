{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    beamdev.url = "git+https://tangled.org/adam.robins.wtf/beamdev";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ ];

      flake.nixosModules.default = ./nix/module.nix;

      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      perSystem =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          beamPackages = pkgs.beamMinimal29Packages.overrideScope (
            _: prev: {
              elixir = prev.elixir_1_20;
            }
          );
        in
        {
          packages.default = pkgs.callPackage ./nix/package.nix { inherit beamPackages; };

          checks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
            module = pkgs.testers.runNixOSTest (
              import ./nix/test.nix {
                module = ./nix/module.nix;
                package = config.packages.default;
              }
            );
          };

          devShells.default = pkgs.mkShell {
            packages = [
              beamPackages.erlang
              beamPackages.elixir
              beamPackages.elixir-ls
              beamPackages.hex
              beamPackages.rebar3
              pkgs.esbuild
              pkgs.git
              pkgs.just
              pkgs.sqlite
              inputs.beamdev.packages.${pkgs.stdenv.hostPlatform.system}.default
            ]
            ++ (lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.inotify-tools ]);

            shellHook = ''
              export ERL_AFLAGS="-kernel shell_history enabled -kernel shell_history_file_bytes 1024000"
              export MIX_ESBUILD_PATH="${lib.getExe pkgs.esbuild}"

              if [ ! -e .erlang.cookie ]; then
                ${lib.getExe pkgs.pwgen} -1 16 > .erlang.cookie
              fi
            '';
          };
        };
    };
}
