{ module, package }:
{ lib, ... }:
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

  testScript = ''
    machine.wait_for_unit("git-sync.service")
    machine.wait_for_open_port(4000)
    machine.succeed("curl --fail --show-error http://127.0.0.1:4000/")
    machine.succeed("test -f /var/lib/git-sync/git_sync.db")

    path = machine.succeed(
        "tr '\\0' '\\n' < /proc/$(systemctl show --property MainPID --value git-sync.service)/environ"
        " | sed -n 's/^PATH=//p'"
    )
    for tool in ["git", "ssh", "ssh-agent", "ssh-keygen", "ssh-keyscan"]:
        machine.succeed(f"PATH={path.strip()} command -v {tool}")
  '';
}
