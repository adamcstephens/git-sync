defmodule GitSync.Tools do
  @moduledoc """
  The external programs a sync shells out to.

  A deployment that is missing one of these can do nothing useful, so the
  application refuses to start rather than failing every run with an
  unreadable `:enoent`.
  """

  @required ~w(git sh ssh ssh-add ssh-agent ssh-keygen ssh-keyscan)

  def check!(tools \\ @required) do
    case Enum.reject(tools, &System.find_executable/1) do
      [] -> :ok
      missing -> raise "not on PATH: #{Enum.join(missing, ", ")}"
    end
  end
end
