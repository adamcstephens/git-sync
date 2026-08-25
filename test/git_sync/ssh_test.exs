defmodule GitSync.SshTest do
  use ExUnit.Case, async: true

  alias GitSync.Connection
  alias GitSync.Ssh

  setup do
    dir = Path.join(System.tmp_dir!(), "git-sync-ssh-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    key = Path.join(dir, "id_ed25519")
    {_, 0} = System.cmd("ssh-keygen", ["-t", "ed25519", "-N", "", "-C", "knot", "-f", key])

    %{
      connection: %Connection{
        kind: :tangled,
        base_url: "https://knot.example.com",
        ssh_key: File.read!(key),
        host_key: "knot.example.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIexample"
      },
      fingerprint: fingerprint(key <> ".pub")
    }
  end

  describe "with_agent/2" do
    test "loads the key into an agent the block can reach", context do
      %{connection: connection, fingerprint: fingerprint} = context

      {:ok, identities} = Ssh.with_agent(connection, &ssh_add_list/1)

      assert identities =~ fingerprint
    end

    test "verifies the host against a private known_hosts file", %{connection: connection} do
      {:ok, command} =
        Ssh.with_agent(connection, fn env ->
          command = env(env, "GIT_SSH_COMMAND")
          known_hosts = option(command, "UserKnownHostsFile")

          send(self(), {:known_hosts, File.read!(known_hosts), File.stat!(known_hosts)})
          {:ok, command}
        end)

      assert command =~ "StrictHostKeyChecking=yes"
      assert command =~ "GlobalKnownHostsFile=/dev/null"

      assert_received {:known_hosts, contents, %File.Stat{mode: mode}}
      assert contents == connection.host_key <> "\n"
      assert Bitwise.band(mode, 0o777) == 0o600
    end

    test "ignores identities the host account happens to hold", %{connection: connection} do
      command = connection |> captured_env() |> env("GIT_SSH_COMMAND")

      assert command =~ "-F /dev/null"
      assert option(command, "IdentityFile") == "/dev/null"
    end

    test "stops the agent and removes its files when the block ends", %{connection: connection} do
      socket = connection |> captured_env() |> env("SSH_AUTH_SOCK")

      refute File.exists?(socket)
      refute File.exists?(Path.dirname(socket))
    end

    test "stops the agent when the block raises", %{connection: connection} do
      assert_raise RuntimeError, fn ->
        Ssh.with_agent(connection, fn env ->
          send(self(), {:env, env})
          raise "boom"
        end)
      end

      assert_received {:env, env}
      refute File.exists?(Path.dirname(env(env, "SSH_AUTH_SOCK")))
    end

    test "keeps the agent's paths out of the block's output", %{connection: connection} do
      {:error, output} =
        Ssh.with_agent(connection, fn env -> {:error, env(env, "SSH_AUTH_SOCK")} end)

      refute output =~ System.tmp_dir!()
    end

    test "runs the block untouched for a connection with no key" do
      connection = %Connection{kind: :forgejo, base_url: "https://codeberg.org"}

      assert {:ok, "[]"} == Ssh.with_agent(connection, fn env -> {:ok, "#{inspect(env)}"} end)
    end
  end

  defp ssh_add_list(env) do
    case System.cmd("ssh-add", ["-l"], env: env, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, _} -> {:error, output}
    end
  end

  defp captured_env(connection) do
    {:ok, ""} =
      Ssh.with_agent(connection, fn env ->
        send(self(), {:env, env})
        {:ok, ""}
      end)

    assert_received {:env, env}
    env
  end

  defp env(env, name) do
    {^name, value} = List.keyfind(env, name, 0)
    value
  end

  defp option(command, name) do
    [_, value] = Regex.run(~r/-o #{name}=(\S+)/, command)
    value
  end

  defp fingerprint(pub) do
    {output, 0} = System.cmd("ssh-keygen", ["-lf", pub])
    output |> String.split(" ") |> Enum.at(1)
  end
end
