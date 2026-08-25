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

  defp scrub({status, output}, dir), do: {status, String.replace(output, dir, "<ssh>")}
end
