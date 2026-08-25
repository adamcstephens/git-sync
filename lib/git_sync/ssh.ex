defmodule GitSync.Ssh do
  @moduledoc """
  Push credentials for forges that speak git over SSH.

  The key lives in an `ssh-agent` started for the invocation and reached
  through a socket in a private directory: it reaches `ssh-add` through the
  environment rather than a file, so it never lands on disk.
  The host is verified against the connection's own `known_hosts`, holding
  whatever `ssh-keyscan` reported for the knot.
  """

  alias GitSync.Connection

  @add ~s(printf '%s' "$GIT_SYNC_SSH_KEY" | ssh-add -)

  @timeout "5"

  @options [
    "-F /dev/null",
    "-o StrictHostKeyChecking=yes",
    "-o GlobalKnownHostsFile=/dev/null",
    "-o IdentityFile=/dev/null"
  ]

  @doc """
  Runs `fun` with the environment that authenticates one git invocation
  against `connection`, tearing the agent down afterwards.

  `fun` takes the environment and returns a `{status, output}` pair; the
  agent's paths are scrubbed from the output so they cannot reach a run log.
  A connection with no key runs the block with an empty environment.
  """
  def with_agent(%Connection{ssh_key: key} = connection, fun) when is_binary(key) do
    dir = private_dir()

    try do
      socket = Path.join(dir, "agent")
      known_hosts = Path.join(dir, "known_hosts")

      write(known_hosts, connection.host_key)

      case start_agent(socket) do
        {:ok, pid} ->
          try do
            case add_key(socket, key) do
              :ok -> fun.(env(socket, known_hosts))
              {:error, output} -> {:error, output}
            end
          after
            stop_agent(pid)
          end

        {:error, output} ->
          {:error, output}
      end
      |> scrub(dir)
    after
      File.rm_rf!(dir)
    end
  end

  def with_agent(%Connection{}, fun), do: fun.([])

  @doc """
  Generates the keypair git-sync pushes with. The operator never sees the
  private half; the public half is theirs to add to the knot.
  """
  def generate_key do
    dir = private_dir()
    path = Path.join(dir, "id_ed25519")

    try do
      case System.cmd("ssh-keygen", ~w(-q -t ed25519 -N) ++ ["", "-C", "git-sync", "-f", path],
             stderr_to_stdout: true
           ) do
        {_output, 0} -> {:ok, %{private: File.read!(path), public: File.read!(path <> ".pub")}}
        {output, _} -> {:error, scrub_dir(output, dir)}
      end
    after
      File.rm_rf!(dir)
    end
  end

  @doc """
  Asks a host which keys it identifies itself by, in `known_hosts` form.

  This is trust on first use: whatever answers on the wire is what gets
  believed. Show `fingerprints/1` of the result to whoever is setting the
  connection up so they can check it against what the host's operator
  publishes.
  """
  def scan_host(host, port \\ default_port()) do
    {output, _status} =
      System.cmd("ssh-keyscan", ["-T", @timeout, "-p", "#{port}", host], stderr_to_stdout: true)

    case keys(output) do
      [] -> {:error, "no host keys came back from #{host}"}
      keys -> {:ok, Enum.join(keys, "\n") <> "\n"}
    end
  end

  @doc """
  The fingerprints of every key in a `known_hosts` blob, for an operator to
  compare against the host they meant to reach. Anything unreadable fingerprints
  as nothing.
  """
  def fingerprints(blob) when blob in [nil, ""], do: []

  def fingerprints(blob) do
    dir = private_dir()
    path = Path.join(dir, "known_hosts")

    try do
      write(path, blob)

      case System.cmd("ssh-keygen", ["-lf", path], stderr_to_stdout: true) do
        {output, 0} -> Enum.map(lines(output), &Enum.at(String.split(&1, " "), 1))
        {_output, _} -> []
      end
    after
      File.rm_rf!(dir)
    end
  end

  defp default_port, do: Application.get_env(:git_sync, :knot_ssh_port, 22)

  defp keys(output), do: Enum.reject(lines(output), &String.starts_with?(&1, "#"))

  defp lines(output), do: output |> String.split("\n", trim: true) |> Enum.map(&String.trim/1)

  defp env(socket, known_hosts) do
    command = Enum.join(["ssh" | @options] ++ ["-o UserKnownHostsFile=#{known_hosts}"], " ")

    [{"SSH_AUTH_SOCK", socket}, {"GIT_SSH_COMMAND", command}]
  end

  defp start_agent(socket) do
    case System.cmd("ssh-agent", ["-a", socket], stderr_to_stdout: true) do
      {output, 0} -> {:ok, agent_pid(output)}
      {output, _} -> {:error, output}
    end
  end

  defp agent_pid(output) do
    [pid] = Regex.run(~r/SSH_AGENT_PID=(\d+)/, output, capture: :all_but_first)
    pid
  end

  defp stop_agent(pid) do
    System.cmd("ssh-agent", ["-k"], env: [{"SSH_AGENT_PID", pid}], stderr_to_stdout: true)
  end

  defp add_key(socket, key) do
    env = [{"SSH_AUTH_SOCK", socket}, {"GIT_SYNC_SSH_KEY", key}]

    case System.cmd("sh", ["-c", @add], env: env, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _} -> {:error, output}
    end
  end

  defp private_dir do
    path =
      Path.join(System.tmp_dir!(), "git-sync-ssh-#{System.unique_integer([:positive])}")

    File.mkdir_p!(path)
    File.chmod!(path, 0o700)
    path
  end

  defp write(path, contents) do
    File.write!(path, String.trim_trailing("#{contents}") <> "\n")
    File.chmod!(path, 0o600)
  end

  defp scrub({status, output}, dir), do: {status, scrub_dir(output, dir)}

  defp scrub_dir(output, dir), do: String.replace(output, dir, "<ssh>")
end
