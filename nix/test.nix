{ module, package }:
{ lib, hostPkgs, ... }:
{
  name = "git-sync";

  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [ module ];

      services.git-sync = {
        enable = true;
        package = package;
        host = "git-sync.example.com";
        address = "127.0.0.1";
        secretsFile = pkgs.writeText "git-sync.env" ''
          SECRET_KEY_BASE=${lib.strings.replicate 64 "a"}
          CLOAK_KEY=${lib.strings.replicate 43 "b"}=
        '';
      };
    };

  testScript =
    { nodes, ... }:
    let
      inherit (nodes.machine.systemd.services.git-sync) serviceConfig;

      sandbox = lib.concatMapStringsSep " " (property: "--property=${lib.escapeShellArg property}") (
        map (call: "SystemCallFilter=${call}") serviceConfig.SystemCallFilter
        ++ [
          "SystemCallArchitectures=${serviceConfig.SystemCallArchitectures}"
          "SystemCallErrorNumber=${serviceConfig.SystemCallErrorNumber}"
        ]
      );

      denied = hostPkgs.writeShellScript "denied-syscall" ''
        ${lib.getExe' hostPkgs.coreutils "chroot"} / ${lib.getExe' hostPkgs.coreutils "true"}
        status=$?
        test "$status" -ne 0 && test "$status" -lt 128
      '';

      keypair = lib.concatStringsSep " " [
        "{:ok, key} = GitSync.Ssh.generate_key();"
        "{:ok, identities} = GitSync.Ssh.with_agent("
        "%GitSync.Connection{ssh_key: key.private},"
        ''"knot.example.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIexample",''
        ''fn env -> {out, 0} = System.cmd("ssh-add", ["-l"], env: env); {:ok, out} end);''
        ''true = String.contains?(identities, "git-sync")''
      ];
    in
    ''
      machine.wait_for_unit("git-sync.service")
      machine.wait_for_open_port(4000)
      machine.succeed("curl --fail --show-error http://127.0.0.1:4000/")
      machine.succeed("test -f /var/lib/git-sync/git_sync.db")

      machine.succeed(
          "tr '\\0' '\\n' < /proc/$(systemctl show --property MainPID --value git-sync.service)/environ"
          " > /run/service.env"
      )

      path = machine.succeed("sed -n 's/^PATH=//p' /run/service.env").strip()
      for tool in ["git", "ssh", "ssh-agent", "ssh-keygen", "ssh-keyscan"]:
          machine.succeed(f"PATH={path} command -v {tool}")

      with subtest("the sandbox permits everything an ssh keypair needs"):
          machine.succeed(
              "grep --invert-match --extended-regexp '^(HOME|RELEASE_TMP)=' /run/service.env > /run/probe.env",
              "install -d -m 700 /run/probe",
          )
          machine.succeed(
              """systemd-run --wait --pipe --collect"""
              """ ${sandbox}"""
              """ --property=EnvironmentFile=/run/probe.env"""
              """ --property=Environment=HOME=/run/probe"""
              """ --property=Environment=RELEASE_TMP=/run/probe"""
              """ ${lib.getExe package} eval '${keypair}'"""
          )

      with subtest("a denied syscall fails the call rather than killing the caller"):
          machine.succeed("systemd-run --wait --pipe --collect ${sandbox} ${denied}")
    '';
}
