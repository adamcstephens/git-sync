{
  bash,
  lib,
  beamMinimal29Packages,
  esbuild,
  git,
  makeWrapper,
  openssh,
}:

let
  beamPackages = beamMinimal29Packages.overrideScope (
    _: prev: {
      elixir = prev.elixir_1_20;
    }
  );
in
beamPackages.mixRelease rec {
  pname = "git-sync";
  version = "0.1.0";

  MIX_ESBUILD_PATH = lib.getExe esbuild;

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

  mixFodDeps = beamPackages.fetchMixDeps {
    pname = "${pname}-deps";
    inherit src version MIX_ESBUILD_PATH;
    hash = "sha256-dU5V1UQ/ztU5LQVR4e2/fCupJihKVEpZJOezdqK+s2M=";
  };

  nativeBuildInputs = [ makeWrapper ];

  # exqlite otherwise tries to download a precompiled NIF into a cache under $HOME.
  FORCE_BUILD = "1";

  preConfigure = ''
    export ELIXIR_MAKE_CACHE_DIR=$TEMPDIR/elixir_make
  '';

  preBuild = ''
    mix assets.deploy --no-deps-check
  '';

  postFixup = ''
    wrapProgram $out/bin/git_sync \
      --prefix PATH : ${
        lib.makeBinPath [
          bash
          git
          openssh
        ]
      }
  '';

  meta = {
    description = "Mirror git repositories between forges";
    mainProgram = "git_sync";
  };
}
