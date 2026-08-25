defmodule GitSyncWeb.CacheBodyReader do
  @moduledoc """
  Keeps the raw request body for the webhook endpoint, whose signatures are
  computed over the exact bytes the forge sent rather than the parsed params.
  """

  def read_body(%Plug.Conn{path_info: ["webhooks" | _]} = conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    {:ok, body, update_in(conn.assigns[:raw_body], &[body | &1 || []])}
  end

  def read_body(conn, opts), do: Plug.Conn.read_body(conn, opts)

  @doc """
  The bytes the forge signed.
  """
  def raw_body(%Plug.Conn{assigns: %{raw_body: chunks}}), do: IO.iodata_to_binary(chunks)
end
