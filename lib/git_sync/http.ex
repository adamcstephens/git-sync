defmodule GitSync.Http do
  @moduledoc """
  Builds the `Req` request every outbound HTTP call starts from.
  """

  def request(options) do
    :git_sync
    |> Application.get_env(:req_options, [])
    |> Keyword.merge(options)
    |> Req.new()
  end
end
