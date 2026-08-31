{
  bash,
  lib,
  beamPackages,
  callPackages,
  esbuild,
  git,
  openssh,
  sqlite,
}:

beamPackages.mixRelease rec {
  pname = "git-sync";
  version = "0.1.0";

  env.MIX_ESBUILD_PATH = lib.getExe esbuild;

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../assets
      ../config
      ../lib
      ../priv
      ../mix.exs
      ../mix.lock
    ];
  };

  mixNixDeps = callPackages ./deps.nix {
    inherit lib beamPackages;
    overrides = self: prev: {
      exqlite = prev.exqlite.override (old: {
        env = (old.env or { }) // {
          EXQLITE_USE_SYSTEM = "1";
          EXQLITE_SYSTEM_CFLAGS = "-I${sqlite.dev}/include";
          EXQLITE_SYSTEM_LDFLAGS = "-L${sqlite.out}/lib -lsqlite3";
        };
      });
    };
  };

  preConfigure = ''
    export ELIXIR_MAKE_CACHE_DIR=$TEMPDIR/elixir_make
  '';

  postBuild = ''
    mix do deps.loadpaths --no-deps-check + assets.deploy
  '';

  passthru = {
    inherit mixNixDeps;
  };

  # mixRelease owns postFixup, so the tools we shell out to reach the release
  # through its own environment hook instead of a wrapper.
  postInstall = ''
    echo 'export PATH=${
      lib.makeBinPath [
        bash
        git
        openssh
      ]
    }:$PATH' >> $out/releases/${version}/env.sh
  '';

  meta = {
    description = "Mirror git repositories between forges";
    mainProgram = "git_sync";
  };
}
