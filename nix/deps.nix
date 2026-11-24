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

      argon2_elixir =
        let
          version = "4.1.3";
          drv = buildMix {
            inherit version;
            name = "argon2_elixir";

            src = fetchHex {
              inherit version;
              pkg = "argon2_elixir";
              sha256 = "7c295b8d8e0eaf6f43641698f962526cdf87c6feb7d14bd21e599271b510608c";
            };

            beamDeps = [
              comeonin
              elixir_make
            ];
          };
        in
        drv.override (workarounds.elixirMake { } drv);

      bandit =
        let
          version = "1.15.0";
          drv = buildMix {
            inherit version;
            name = "bandit";

            src = fetchHex {
              inherit version;
              pkg = "bandit";
              sha256 = "e3b29c4a5107f4bf7dfaa263c50b9b97ddcc132622197c110e2e10a921641c44";
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

      comeonin =
        let
          version = "5.5.1";
          drv = buildMix {
            inherit version;
            name = "comeonin";

            src = fetchHex {
              inherit version;
              pkg = "comeonin";
              sha256 = "65aac8f19938145377cee73973f192c5645873dcf550a8a6b18187d17c13ccdb";
            };
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
          version = "3.2.0";
          drv = buildMix {
            inherit version;
            name = "decimal";

            src = fetchHex {
              inherit version;
              pkg = "decimal";
              sha256 = "190bca80580ce61aa69bb0eacadd7677710205c770225c2c2c07e32a5c31b234";
            };
          };
        in
        drv;

      ecto =
        let
          version = "3.14.3";
          drv = buildMix {
            inherit version;
            name = "ecto";

            src = fetchHex {
              inherit version;
              pkg = "ecto";
              sha256 = "da2548bd3ced0f56c27d54255389bbbb8f110150ce15cffc95ec0cafa364465c";
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
          version = "0.26.0";
          drv = buildMix {
            inherit version;
            name = "ecto_sqlite3";

            src = fetchHex {
              inherit version;
              pkg = "ecto_sqlite3";
              sha256 = "e04d69e185f27a604dd116144a1bad36595666546d753e9341a3f3736ee64772";
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
          version = "0.10.1";
          drv = buildMix {
            inherit version;
            name = "elixir_make";

            src = fetchHex {
              inherit version;
              pkg = "elixir_make";
              sha256 = "ce1eaa234bc87f0279718e793fd6f8ad35b4e8ee8d412329e3879eee8d40adba";
            };
          };
        in
        drv;

      envar =
        let
          version = "1.1.0";
          drv = buildMix {
            inherit version;
            name = "envar";

            src = fetchHex {
              inherit version;
              pkg = "envar";
              sha256 = "97028ab4a040a5c19e613fdf46a41cf51c6e848d99077e525b338e21d2993320";
            };
          };
        in
        drv;

      esbuild =
        let
          version = "0.10.1";
          drv = buildMix {
            inherit version;
            name = "esbuild";

            src = fetchHex {
              inherit version;
              pkg = "esbuild";
              sha256 = "890f251330052dcacafa40c409769e7c42e3876fb0ae450707bde831be7b34ea";
            };

            beamDeps = [
              jason
            ];
          };
        in
        drv;

      exqlite =
        let
          version = "0.43.0";
          drv = buildMix {
            inherit version;
            name = "exqlite";

            src = fetchHex {
              inherit version;
              pkg = "exqlite";
              sha256 = "aa9996f5f582b01f641076632a03bfe139655606b2ba2c86bf528656adf22a5a";
            };

            beamDeps = [
              cc_precompiler
              db_connection
              elixir_make
            ];
          };
        in
        drv.override (workarounds.elixirMake { } drv);

      fields =
        let
          version = "2.12.0";
          drv = buildMix {
            inherit version;
            name = "fields";

            src = fetchHex {
              inherit version;
              pkg = "fields";
              sha256 = "6174a777fa37207470f925488e44ccc1a4974da672e6bfcc05441c8b83c2d844";
            };

            beamDeps = [
              argon2_elixir
              ecto
              envar
              html_sanitize_ex
            ];
          };
        in
        drv;

      finch =
        let
          version = "0.25.0";
          drv = buildMix {
            inherit version;
            name = "finch";

            src = fetchHex {
              inherit version;
              pkg = "finch";
              sha256 = "9fd9a2c47a9033f4d70fad6e7d656948c08bc6652699de20e609a5917c0bb0a5";
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
          version = "1.1.0";
          drv = buildMix {
            inherit version;
            name = "hpax";

            src = fetchHex {
              inherit version;
              pkg = "hpax";
              sha256 = "0b8d0f05832f55571d65ac720f79bf8994138ffbb133209dc4685eae0ad456a8";
            };
          };
        in
        drv;

      html_sanitize_ex =
        let
          version = "1.5.6";
          drv = buildMix {
            inherit version;
            name = "html_sanitize_ex";

            src = fetchHex {
              inherit version;
              pkg = "html_sanitize_ex";
              sha256 = "b7592ad4a6d8d509b84e2dd3b2e4db4ed61315da711c8d98c68d4e9546c40df4";
            };

            beamDeps = [
              mochiweb
            ];
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
          version = "1.11.13";
          drv = buildMix {
            inherit version;
            name = "jose";

            src = fetchHex {
              inherit version;
              pkg = "jose";
              sha256 = "15d8bd0f01ab29d1771e8da1f60f9c98725b23a17f7312cdd40e8e2757bd98c7";
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
          version = "1.11.0";
          drv = buildMix {
            inherit version;
            name = "mint";

            src = fetchHex {
              inherit version;
              pkg = "mint";
              sha256 = "c6279ba2d6aa3a383a1d4cfbe7b59f42e6efd400f58d8e2acfeac48a438693ab";
            };

            beamDeps = [
              hpax
            ];
          };
        in
        drv;

      mochiweb =
        let
          version = "3.6.1";
          drv = buildRebar3 {
            inherit version;
            name = "mochiweb";

            src = fetchHex {
              inherit version;
              pkg = "mochiweb";
              sha256 = "23bc48bc8a129b4e894648c01a1ec77405e879b8b3d7e170711cca6ac1dc819c";
            };
          };
        in
        drv;

      nimble_options =
        let
          version = "1.2.0";
          drv = buildMix {
            inherit version;
            name = "nimble_options";

            src = fetchHex {
              inherit version;
              pkg = "nimble_options";
              sha256 = "3a784a75ef9e407619c8c9e98239b1acd29216deb737044a8c1063e2671ce6d9";
            };
          };
        in
        drv;

      nimble_pool =
        let
          version = "1.2.0";
          drv = buildMix {
            inherit version;
            name = "nimble_pool";

            src = fetchHex {
              inherit version;
              pkg = "nimble_pool";
              sha256 = "bc442e72578c21842589fa8e5886b6175fa5245fdbbad35fc08db277ac2b2c0d";
            };
          };
        in
        drv;

      oidcc =
        let
          version = "3.9.2";
          drv = buildMix {
            inherit version;
            name = "oidcc";

            src = fetchHex {
              inherit version;
              pkg = "oidcc";
              sha256 = "e469213a2518904e805ff4f8325a405ac740a74a381e711968d32636c10d9c9b";
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
          version = "0.5.2";
          drv = buildMix {
            inherit version;
            name = "oidcc_plug";

            src = fetchHex {
              inherit version;
              pkg = "oidcc_plug";
              sha256 = "047f46332a88d9046c49628a57d4f6031342b2864342eb379440ac5d4e747d2b";
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
          version = "1.8.17";
          drv = buildMix {
            inherit version;
            name = "phoenix";

            src = fetchHex {
              inherit version;
              pkg = "phoenix";
              sha256 = "21fd4d6a33c6af4e86b95156a49815a59140c2ba4ef8cf19565dbb7be881633e";
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
          version = "4.4.0";
          drv = buildMix {
            inherit version;
            name = "phoenix_html";

            src = fetchHex {
              inherit version;
              pkg = "phoenix_html";
              sha256 = "94832038da7ab8f86d4c0d36f7797a269fd06fe611f25c69f55108c075505228";
            };
          };
        in
        drv;

      phoenix_live_view =
        let
          version = "1.2.15";
          drv = buildMix {
            inherit version;
            name = "phoenix_live_view";

            src = fetchHex {
              inherit version;
              pkg = "phoenix_live_view";
              sha256 = "06de7d327a964c81e93a4d64f67088852bf3512f30c04af563101feaac1deaf1";
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
          version = "2.4.1";
          drv = buildMix {
            inherit version;
            name = "phoenix_pubsub";

            src = fetchHex {
              inherit version;
              pkg = "phoenix_pubsub";
              sha256 = "352fba7a87bf61395b6e97da66944ad9b1bfe5459e5981039f60d68270bd9700";
            };
          };
        in
        drv;

      phoenix_template =
        let
          version = "1.1.0";
          drv = buildMix {
            inherit version;
            name = "phoenix_template";

            src = fetchHex {
              inherit version;
              pkg = "phoenix_template";
              sha256 = "eba70070de79b2c3501ef205a74a69f98ab352f3785aa15da9ed161f9fe0fd5d";
            };

            beamDeps = [
              phoenix_html
            ];
          };
        in
        drv;

      plug =
        let
          version = "1.20.4";
          drv = buildMix {
            inherit version;
            name = "plug";

            src = fetchHex {
              inherit version;
              pkg = "plug";
              sha256 = "96ee42c0b8b35bcb14e3e65afb85abe9bb7745a8576e8c602802bbb01e5acf72";
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
          version = "2.2.1";
          drv = buildMix {
            inherit version;
            name = "plug_crypto";

            src = fetchHex {
              inherit version;
              pkg = "plug_crypto";
              sha256 = "4417ccbd8f85e627321cd07d2ab9c4b621f1fd883b9905af241f9b4b780b94b6";
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
          version = "1.4.3";
          drv = buildRebar3 {
            inherit version;
            name = "telemetry";

            src = fetchHex {
              inherit version;
              pkg = "telemetry";
              sha256 = "17a63581cf2e832a238287f5fe6811e8ca1f333249f1376ad653164a3c4770d4";
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
          version = "1.6.0";
          drv = buildMix {
            inherit version;
            name = "thousand_island";

            src = fetchHex {
              inherit version;
              pkg = "thousand_island";
              sha256 = "4d4720470f091fc21a1311777c2ac66916c43621bffc068590c9f9bb3cd057a3";
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
          version = "0.7.2";
          drv = buildMix {
            inherit version;
            name = "websock_adapter";

            src = fetchHex {
              inherit version;
              pkg = "websock_adapter";
              sha256 = "f9e80710008783864177c81e9d8418d05769ce10a26e9e538f5ed72e283f7358";
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
