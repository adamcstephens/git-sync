defmodule GitSync.Knot do
  @moduledoc """
  A throwaway SSH server for tests that need a host to scan keys from.

  `serve/0` points the knot SSH port at it for the duration of the test, so
  code that reaches for a knot's host keys finds this one.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  @doc """
  Starts a server on loopback and returns its port and the public half of the
  host key it identifies itself by.
  """
  def serve do
    {:ok, _started} = Application.ensure_all_started(:ssh)

    dir = scratch()
    key = Path.join(dir, "ssh_host_ed25519_key")
    {_output, 0} = System.cmd("ssh-keygen", ["-t", "ed25519", "-N", "", "-f", key])

    {:ok, ref} =
      :ssh.daemon({127, 0, 0, 1}, 0,
        system_dir: to_charlist(dir),
        auth_methods: ~c"password",
        user_passwords: [{~c"nobody", ~c"nothing"}]
      )

    on_exit(fn -> :ssh.stop_daemon(ref) end)

    {:ok, info} = :ssh.daemon_info(ref)
    port = Keyword.fetch!(info, :port)

    put_port(port)

    %{port: port, public: File.read!(key <> ".pub")}
  end

  @doc """
  A port nothing is listening on, for the case where a knot cannot be reached.
  """
  def refuse do
    {:ok, socket} = :gen_tcp.listen(0, ifaddr: {127, 0, 0, 1})
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)

    put_port(port)

    port
  end

  @doc """
  The fingerprint of a public key, in the form `ssh-keygen -l` reports.
  """
  def fingerprint(public) do
    path = Path.join(scratch(), "key.pub")
    File.write!(path, public)

    {output, 0} = System.cmd("ssh-keygen", ["-lf", path])

    output |> String.split(" ") |> Enum.at(1)
  end

  defp put_port(port) do
    Application.put_env(:git_sync, :knot_ssh_port, port)
    on_exit(fn -> Application.delete_env(:git_sync, :knot_ssh_port) end)
  end

  defp scratch do
    dir = Path.join(System.tmp_dir!(), "git-sync-knot-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    dir
  end
end
