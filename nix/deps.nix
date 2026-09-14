{
  lib,
  beamPackages,
  cmake,
  extend,
  lexbor,
  fetchFromGitHub,
  oniguruma,
  overrides ? (x: y: { }),
  overrideFenixOverlay ? null,
  rustlerPrecompiledOverrides ? { },
  stdenv,
  pkg-config,
  vips,
  writeText,
}:

let
  buildMix = lib.makeOverridable beamPackages.buildMix;
  buildRebar3 = lib.makeOverridable beamPackages.buildRebar3;

  workarounds = {
    portCompiler = _unusedArgs: old: {
      buildPlugins = [ beamPackages.pc ];
    };

    rustlerPrecompiled =
      {
        toolchain ? null,
        buildInputs ? [ ],
        nativeBuildInputs ? [ ],
        env ? { },
        ...
      }:
      old:
      let
        extendedPkgs = extend fenixOverlay;
        fenixOverlay =
          if overrideFenixOverlay == null then
            import "${
              fetchTarball {
                url = "https://github.com/nix-community/fenix/archive/6399553b7a300c77e7f07342904eb696a5b6bf9d.tar.gz";
                sha256 = "sha256-C6tT7K1Lx6VsYw1BY5S3OavtapUvEnDQtmQB5DSgbCc=";
              }
            }/overlay.nix"
          else
            overrideFenixOverlay;
        nativeDir = "${old.src}/native/${with builtins; head (attrNames (readDir "${old.src}/native"))}";
        fenix =
          if toolchain == null then
            extendedPkgs.fenix.stable
          else
            extendedPkgs.fenix.fromToolchainName toolchain;
        native =
          (
            (extendedPkgs.makeRustPlatform {
              inherit (fenix) cargo rustc;
            }).buildRustPackage
            {
              inherit env buildInputs;
              pname = "${old.beamModuleName}-native";
              version = old.version;
              src = nativeDir;
              cargoLock = {
                lockFile = "${nativeDir}/Cargo.lock";
              };
              nativeBuildInputs = [ extendedPkgs.cmake ] ++ nativeBuildInputs;
              doCheck = false;
            }
          ).overrideAttrs
            rustlerPrecompiledOverrides.${old.beamModuleName} or { };

      in
      {
        nativeBuildInputs = [ extendedPkgs.cargo ];

        env.RUSTLER_PRECOMPILED_FORCE_BUILD_ALL = "true";
        env.RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH = "unused-but-required";

        preConfigure = ''
          mkdir -p priv/native
          for lib in ${native}/lib/*
          do
            dest="$(basename "$lib")"
            if [[ "''${dest##*.}" = "dylib" ]]
            then
              dest="''${dest%.dylib}.so"
            fi
            dest="''${dest#lib}"
            ln -s "$lib" "priv/native/$dest"
          done
        '';

        preBuild = ''
          suggestion() {
            echo "***********************************************"
            echo "                 deps_nix                      "
            echo
            echo " Rust dependency build failed.                 "
            echo
            echo " If you saw network errors, you might need     "
            echo " to disable compilation on the appropriate     "
            echo " RustlerPrecompiled module in your             "
            echo " application config.                           "
            echo
            echo " We think you need this:                       "
            echo
            echo -n " "
            grep -Rl 'use RustlerPrecompiled' lib \
              | xargs grep 'defmodule' \
              | sed 's/defmodule \(.*\) do/config :${old.beamModuleName}, \1, skip_compilation?: true/'
            echo "***********************************************"
            exit 1
          }
          trap suggestion ERR
        '';
      };

    elixirMake = _unusedArgs: old: {
      preConfigure = ''
        export ELIXIR_MAKE_CACHE_DIR="$TEMPDIR/elixir_make_cache"
      '';
    };

    lazyHtml = _unusedArgs: old: {
      preConfigure = ''
        export ELIXIR_MAKE_CACHE_DIR="$TEMPDIR/elixir_make_cache"
      '';

      postPatch = ''
        substituteInPlace mix.exs \
          --replace-fail "Fine.include_dir()" '"${packages.fine}/src/c_include"' \
          --replace-fail '@lexbor_git_sha "244b84956a6dc7eec293781d051354f351274c46"' '@lexbor_git_sha ""'
      '';

      preBuild = ''
        install -Dm644           -t _build/c/third_party/lexbor/$LEXBOR_GIT_SHA/build           ${lexbor}/lib/liblexbor_static.a
      '';
    };
  };

  defaultOverrides = (
    final: prev:

    let
      apps = {
        crc32cer = [
          {
            name = "portCompiler";
          }
        ];
        explorer = [
          {
            name = "rustlerPrecompiled";
            toolchain = {
              name = "nightly-2025-06-23";
              sha256 = "sha256-UAoZcxg3iWtS+2n8TFNfANFt/GmkuOMDf7QAE0fRxeA=";
            };
          }
        ];
        snappyer = [
          {
            name = "portCompiler";
          }
        ];
      };

      applyOverrides =
        appName: drv:
        let
          allOverridesForApp = builtins.foldl' (
            acc: workaround: acc // (workarounds.${workaround.name} workaround) drv
          ) { } apps.${appName};

        in
        if builtins.hasAttr appName apps then drv.override allOverridesForApp else drv;

    in
    builtins.mapAttrs applyOverrides prev
  );

  self = packages // (defaultOverrides self packages) // (overrides self packages);

  packages =
    with beamPackages;
    with self;
    {

      bandit =
        let
          version = "1.12.5";
          drv = buildMix {
            inherit version;
            name = "bandit";

            src = fetchHex {
              inherit version;
              pkg = "bandit";
              sha256 = "c5684ca062fa407cac115aec3256383f3e2ec9fdced7904d59cf5a7bb7ed6181";
            };

            beamDeps = [
              hpax
              plug
              telemetry
              thousand_island
              websock
            ];
          };
        in
        drv;

      cc_precompiler =
        let
          version = "0.1.11";
          drv = buildMix {
            inherit version;
            name = "cc_precompiler";

            src = fetchHex {
              inherit version;
              pkg = "cc_precompiler";
              sha256 = "3427232caf0835f94680e5bcf082408a70b48ad68a5f5c0b02a3bea9f3a075b9";
            };

            beamDeps = [
              elixir_make
            ];
          };
        in
        drv.override (workarounds.elixirMake { } drv);

      cloak =
        let
          version = "1.1.4";
          drv = buildMix {
            inherit version;
            name = "cloak";

            src = fetchHex {
              inherit version;
              pkg = "cloak";
              sha256 = "92b20527b9aba3d939fab0dd32ce592ff86361547cfdc87d74edce6f980eb3d7";
            };

            beamDeps = [
              jason
            ];
          };
        in
        drv;

      cloak_ecto =
        let
          version = "1.3.0";
          drv = buildMix {
            inherit version;
            name = "cloak_ecto";

            src = fetchHex {
              inherit version;
              pkg = "cloak_ecto";
              sha256 = "314beb0c123b8a800418ca1d51065b27ba3b15f085977e65c0f7b2adab2de1cc";
            };

            beamDeps = [
              cloak
              ecto
            ];
          };
        in
        drv;

      db_connection =
        let
          version = "2.10.2";
          drv = buildMix {
            inherit version;
            name = "db_connection";

            src = fetchHex {
              inherit version;
              pkg = "db_connection";
              sha256 = "510b14482330f1af6490a2fa0efd8d4f1435d1529b165647df22ac0f2df0fa93";
            };

            beamDeps = [
              telemetry
            ];
          };
        in
        drv;

      decimal =
        let
          version = "3.1.1";
          drv = buildMix {
            inherit version;
            name = "decimal";

            src = fetchHex {
              inherit version;
              pkg = "decimal";
              sha256 = "c5f25f2ced74a0587d03e6023f595db8e924c9d3922c8c8ffd9edfc4498cf1f6";
            };
          };
        in
        drv;

      ecto =
        let
          version = "3.14.2";
          drv = buildMix {
            inherit version;
            name = "ecto";

            src = fetchHex {
              inherit version;
              pkg = "ecto";
              sha256 = "25d60b8c816a07d19d85b80bdf60978bd8b102209dda198d768cd7c6745339a6";
            };

            beamDeps = [
              decimal
              jason
              telemetry
            ];
          };
        in
        drv;

      ecto_sql =
        let
          version = "3.14.0";
          drv = buildMix {
            inherit version;
            name = "ecto_sql";

            src = fetchHex {
              inherit version;
              pkg = "ecto_sql";
              sha256 = "f4d8d36faf294c9417b5a37ec7ac8217ee2abdef5fcf197ba690f361548d3949";
            };

            beamDeps = [
              db_connection
              decimal
              ecto
              telemetry
            ];
          };
        in
        drv;

      ecto_sqlite3 =
        let
          version = "0.24.1";
          drv = buildMix {
            inherit version;
            name = "ecto_sqlite3";

            src = fetchHex {
              inherit version;
              pkg = "ecto_sqlite3";
              sha256 = "681ca576c74a94944b962eeb7e0cf19aaea517decafd3213afb403ac8f4cd2e3";
            };

            beamDeps = [
              decimal
              ecto
              ecto_sql
              exqlite
            ];
          };
        in
        drv;

      elixir_make =
        let
          version = "0.10.0";
          drv = buildMix {
            inherit version;
            name = "elixir_make";

            src = fetchHex {
              inherit version;
              pkg = "elixir_make";
              sha256 = "dc1f09fb7fa68866b886abd5f0f3c83553b1a19a52359a899e92af1bb3b31982";
            };
          };
        in
        drv;

      esbuild =
        let
          version = "0.10.0";
          drv = buildMix {
            inherit version;
            name = "esbuild";

            src = fetchHex {
              inherit version;
              pkg = "esbuild";
              sha256 = "468489cda427b974a7cc9f03ace55368a83e1a7be12fba7e30969af78e5f8c70";
            };

            beamDeps = [
              jason
            ];
          };
        in
        drv;

      exqlite =
        let
          version = "0.40.0";
          drv = buildMix {
            inherit version;
            name = "exqlite";

            src = fetchHex {
              inherit version;
              pkg = "exqlite";
              sha256 = "f83350f2d29a38be1fd38f39081dd36f41fc51bbacf0f4c2927d01308ae331d0";
            };

            beamDeps = [
              cc_precompiler
              db_connection
              elixir_make
            ];
          };
        in
        drv.override (workarounds.elixirMake { } drv);

      finch =
        let
          version = "0.23.0";
          drv = buildMix {
            inherit version;
            name = "finch";

            src = fetchHex {
              inherit version;
              pkg = "finch";
              sha256 = "80e58d3f936f57e3fdf404f83a3642897ae6d9fb642934e46da4d8fe761b99d5";
            };

            beamDeps = [
              mime
              mint
              nimble_options
              nimble_pool
              telemetry
            ];
          };
        in
        drv;

      hpax =
        let
          version = "1.0.4";
          drv = buildMix {
            inherit version;
            name = "hpax";

            src = fetchHex {
              inherit version;
              pkg = "hpax";
              sha256 = "afc7cb142ebcc2d01ce7816190b98ce5dd49e799111b24249f3443d730f377ca";
            };
          };
        in
        drv;

      jason =
        let
          version = "1.4.5";
          drv = buildMix {
            inherit version;
            name = "jason";

            src = fetchHex {
              inherit version;
              pkg = "jason";
              sha256 = "b0c823996102bcd0239b3c2444eb00409b72f6a140c1950bc8b457d836b30684";
            };

            beamDeps = [
              decimal
            ];
          };
        in
        drv;

      jose =
        let
          version = "1.11.12";
          drv = buildMix {
            inherit version;
            name = "jose";

            src = fetchHex {
              inherit version;
              pkg = "jose";
              sha256 = "31e92b653e9210b696765cdd885437457de1add2a9011d92f8cf63e4641bab7b";
            };
          };
        in
        drv;

      mime =
        let
          version = "2.0.7";
          drv = buildMix {
            inherit version;
            name = "mime";

            src = fetchHex {
              inherit version;
              pkg = "mime";
              sha256 = "6171188e399ee16023ffc5b76ce445eb6d9672e2e241d2df6050f3c771e80ccd";
            };
          };
        in
        drv;

      mint =
        let
          version = "1.10.0";
          drv = buildMix {
            inherit version;
            name = "mint";

            src = fetchHex {
              inherit version;
              pkg = "mint";
              sha256 = "8b16fb72aaa7531d206a1f05e4cc85509ba531ccec7a17a22736c9c95cbb24d1";
            };

            beamDeps = [
              hpax
            ];
          };
        in
        drv;

      nimble_options =
        let
          version = "1.1.1";
          drv = buildMix {
            inherit version;
            name = "nimble_options";

            src = fetchHex {
              inherit version;
              pkg = "nimble_options";
              sha256 = "821b2470ca9442c4b6984882fe9bb0389371b8ddec4d45a9504f00a66f650b44";
            };
          };
        in
        drv;

      nimble_pool =
        let
          version = "1.1.0";
          drv = buildMix {
            inherit version;
            name = "nimble_pool";

            src = fetchHex {
              inherit version;
              pkg = "nimble_pool";
              sha256 = "af2e4e6b34197db81f7aad230c1118eac993acc0dae6bc83bac0126d4ae0813a";
            };
          };
        in
        drv;

      oidcc =
        let
          version = "3.9.0";
          drv = buildMix {
            inherit version;
            name = "oidcc";

            src = fetchHex {
              inherit version;
              pkg = "oidcc";
              sha256 = "5a825092fe9b3214017a5777ba7ed871c6e3ff9532848f600f6c1fe31c5e41ce";
            };

            beamDeps = [
              jose
              telemetry
              telemetry_registry
            ];
          };
        in
        drv;

      oidcc_plug =
        let
          version = "0.5.1";
          drv = buildMix {
            inherit version;
            name = "oidcc_plug";

            src = fetchHex {
              inherit version;
              pkg = "oidcc_plug";
              sha256 = "693299f99ed67600396a770c03c293a3449ba942d14397be0c3495b2ab8c1fc2";
            };

            beamDeps = [
              oidcc
              plug
            ];
          };
        in
        drv;

      phoenix =
        let
          version = "1.8.14";
          drv = buildMix {
            inherit version;
            name = "phoenix";

            src = fetchHex {
              inherit version;
              pkg = "phoenix";
              sha256 = "2782ff375824b2b5e41561fbae4764ee7b875af6898483bca49f24a9d1e37816";
            };

            beamDeps = [
              bandit
              jason
              phoenix_pubsub
              phoenix_template
              plug
              plug_crypto
              telemetry
              websock_adapter
            ];
          };
        in
        drv;

      phoenix_ecto =
        let
          version = "4.7.0";
          drv = buildMix {
            inherit version;
            name = "phoenix_ecto";

            src = fetchHex {
              inherit version;
              pkg = "phoenix_ecto";
              sha256 = "1d75011e4254cb4ddf823e81823a9629559a1be93b4321a6a5f11a5306fbf4cc";
            };

            beamDeps = [
              ecto
              phoenix_html
              plug
            ];
          };
        in
        drv;

      phoenix_html =
        let
          version = "4.3.0";
          drv = buildMix {
            inherit version;
            name = "phoenix_html";

            src = fetchHex {
              inherit version;
              pkg = "phoenix_html";
              sha256 = "3eaa290a78bab0f075f791a46a981bbe769d94bc776869f4f3063a14f30497ad";
            };
          };
        in
        drv;

      phoenix_live_view =
        let
          version = "1.2.11";
          drv = buildMix {
            inherit version;
            name = "phoenix_live_view";

            src = fetchHex {
              inherit version;
              pkg = "phoenix_live_view";
              sha256 = "c4087267cbd4dc4ed7ac36512a97830af8e9c857ca7cb22557f8640fc5f9d306";
            };

            beamDeps = [
              jason
              phoenix
              phoenix_html
              phoenix_template
              plug
              telemetry
            ];
          };
        in
        drv;

      phoenix_pubsub =
        let
          version = "2.3.0";
          drv = buildMix {
            inherit version;
            name = "phoenix_pubsub";

            src = fetchHex {
              inherit version;
              pkg = "phoenix_pubsub";
              sha256 = "eec7be6e9cf02e2551d389b558402d6c637cd3973796326e7ba4bb03c6b2e91d";
            };
          };
        in
        drv;

      phoenix_template =
        let
          version = "1.0.4";
          drv = buildMix {
            inherit version;
            name = "phoenix_template";

            src = fetchHex {
              inherit version;
              pkg = "phoenix_template";
              sha256 = "2c0c81f0e5c6753faf5cca2f229c9709919aba34fab866d3bc05060c9c444206";
            };

            beamDeps = [
              phoenix_html
            ];
          };
        in
        drv;

      plug =
        let
          version = "1.20.3";
          drv = buildMix {
            inherit version;
            name = "plug";

            src = fetchHex {
              inherit version;
              pkg = "plug";
              sha256 = "be266aee1b8536ef6409d58cf39a3121319f0ec47cfa1b24024485aa0e76ad76";
            };

            beamDeps = [
              mime
              plug_crypto
              telemetry
            ];
          };
        in
        drv;

      plug_crypto =
        let
          version = "2.2.0";
          drv = buildMix {
            inherit version;
            name = "plug_crypto";

            src = fetchHex {
              inherit version;
              pkg = "plug_crypto";
              sha256 = "83a95744ab1c75876542b6fab135fcc176280e0f301a111c1f757fddcec95d2c";
            };
          };
        in
        drv;

      req =
        let
          version = "0.8.0-rc.0";
          drv = buildMix {
            inherit version;
            name = "req";

            src = fetchHex {
              inherit version;
              pkg = "req";
              sha256 = "f071cc7bc2bd4ace1a86d7f24b98e7aa2c57cecb228b217e5eb667c934229347";
            };

            beamDeps = [
              finch
              mime
              plug
              server_sent_events
            ];
          };
        in
        drv;

      server_sent_events =
        let
          version = "1.1.0";
          drv = buildMix {
            inherit version;
            name = "server_sent_events";

            src = fetchHex {
              inherit version;
              pkg = "server_sent_events";
              sha256 = "8e164db8e295a2d869a8faafbf4a1eeaa749b62fe93f66271adff6394d93ce15";
            };
          };
        in
        drv;

      telemetry =
        let
          version = "1.4.2";
          drv = buildRebar3 {
            inherit version;
            name = "telemetry";

            src = fetchHex {
              inherit version;
              pkg = "telemetry";
              sha256 = "928f6495066506077862c0d1646609eed891a4326bee3126ba54b60af61febb1";
            };
          };
        in
        drv;

      telemetry_metrics =
        let
          version = "1.2.0";
          drv = buildMix {
            inherit version;
            name = "telemetry_metrics";

            src = fetchHex {
              inherit version;
              pkg = "telemetry_metrics";
              sha256 = "71dde12fc29b58b9c77ec17ec319109e5ca848d010fc1965ed4463bba1837c07";
            };

            beamDeps = [
              telemetry
            ];
          };
        in
        drv;

      telemetry_poller =
        let
          version = "1.3.0";
          drv = buildRebar3 {
            inherit version;
            name = "telemetry_poller";

            src = fetchHex {
              inherit version;
              pkg = "telemetry_poller";
              sha256 = "51f18bed7128544a50f75897db9974436ea9bfba560420b646af27a9a9b35211";
            };

            beamDeps = [
              telemetry
            ];
          };
        in
        drv;

      telemetry_registry =
        let
          version = "0.3.2";
          drv = buildMix {
            inherit version;
            name = "telemetry_registry";

            src = fetchHex {
              inherit version;
              pkg = "telemetry_registry";
              sha256 = "e7ed191eb1d115a3034af8e1e35e4e63d5348851d556646d46ca3d1b4e16bab9";
            };

            beamDeps = [
              telemetry
            ];
          };
        in
        drv;

      thousand_island =
        let
          version = "1.5.0";
          drv = buildMix {
            inherit version;
            name = "thousand_island";

            src = fetchHex {
              inherit version;
              pkg = "thousand_island";
              sha256 = "708923d40523e43cf99041ab37a0d4b0ec426ac6438fa3716ab23d919eaeb412";
            };

            beamDeps = [
              telemetry
            ];
          };
        in
        drv;

      websock =
        let
          version = "0.5.3";
          drv = buildMix {
            inherit version;
            name = "websock";

            src = fetchHex {
              inherit version;
              pkg = "websock";
              sha256 = "6105453d7fac22c712ad66fab1d45abdf049868f253cf719b625151460b8b453";
            };
          };
        in
        drv;

      websock_adapter =
        let
          version = "0.6.0";
          drv = buildMix {
            inherit version;
            name = "websock_adapter";

            src = fetchHex {
              inherit version;
              pkg = "websock_adapter";
              sha256 = "50021a85bce8f203b086705d9e0c5415e2c7eb05d319111b0428fe71f9934617";
            };

            beamDeps = [
              bandit
              plug
              websock
            ];
          };
        in
        drv;

    };
in
self
