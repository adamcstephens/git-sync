defmodule GitSync.Git do
  @moduledoc """
  Runs `git`, capturing stdout and stderr together.
  """

  @env [{"GIT_TERMINAL_PROMPT", "0"}, {"GIT_CONFIG_NOSYSTEM", "1"}]

  def run(args, opts \\ []) do
    options = Keyword.merge([stderr_to_stdout: true, env: @env], opts)

    case System.cmd("git", args, options) do
      {output, 0} -> {:ok, output}
      {output, _} -> {:error, output}
    end
  end
end
