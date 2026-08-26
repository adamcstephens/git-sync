{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.git-sync;
in
{
  options.services.git-sync = {
    enable = lib.mkEnableOption "git-sync, a git repository mirroring service";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "The git-sync package to run.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      description = "Public hostname the service is reached at, used to build OAuth redirect URIs.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 4000;
      description = "Port the HTTP endpoint listens on.";
    };

    address = lib.mkOption {
      type = lib.types.str;
      default = "::1";
      description = "Address the HTTP endpoint binds to.";
    };

    secretsFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        EnvironmentFile holding `SECRET_KEY_BASE` and `CLOAK_KEY`. Generate them with
        `mix phx.gen.secret` and
        `elixir -e 'IO.puts(Base.encode64(:crypto.strong_rand_bytes(32)))'`.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open {option}`services.git-sync.port` in the firewall.";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

    systemd.services.git-sync = {
      description = "git-sync repository mirroring";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      environment = {
        PHX_SERVER = "true";
        PHX_HOST = cfg.host;
        PORT = toString cfg.port;
        BIND_ADDRESS = cfg.address;
        DATABASE_PATH = "/var/lib/git-sync/git_sync.db";
        WORKSPACE_ROOT = "/var/lib/git-sync/workspaces";
        HOME = "/var/lib/git-sync";
        RELEASE_TMP = "/run/git-sync";
        RELEASE_DISTRIBUTION = "none";
        RELEASE_COOKIE = "git-sync";
      };

      serviceConfig = {
        Type = "exec";
        ExecStart = "${lib.getExe cfg.package} start";
        EnvironmentFile = cfg.secretsFile;
        Restart = "on-failure";

        DynamicUser = true;
        StateDirectory = "git-sync";
        RuntimeDirectory = "git-sync";
        WorkingDirectory = "/var/lib/git-sync";

        CapabilityBoundingSet = [ "" ];
        LockPersonality = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
        ];
      };
    };
  };
}
