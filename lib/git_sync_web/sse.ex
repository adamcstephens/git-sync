defmodule GitSyncWeb.SSE do
  @moduledoc """
  Emits the Datastar SSE wire protocol over a chunked connection.

  Datastar reads two event types: `datastar-patch-elements` patches markup
  into the DOM, `datastar-patch-signals` patches the client-side signal store.
  """

  import Plug.Conn

  @keepalive_ms 30_000

  @doc """
  Puts the connection into event-stream mode, ready for frames.
  """
  def open(conn) do
    conn =
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> send_chunked(200)

    # `send_chunked/2` notifies the connection owner, which is the process
    # about to sit in `stream/3` reading its own mailbox.
    receive do
      {:plug_conn, :sent} -> conn
    after
      0 -> conn
    end
  end

  @doc """
  Patches `elements` into the DOM. Pass `:selector` to target an element other
  than the one the markup's id names, and `:mode` for any patch mode other
  than `:outer` — `:remove` takes a selector and no elements.
  """
  def patch_elements(conn, elements, opts \\ []) do
    lines =
      data("selector", opts[:selector]) ++
        data("mode", opts[:mode]) ++
        data("useViewTransition", opts[:use_view_transition]) ++
        data("elements", elements)

    frame(conn, "datastar-patch-elements", lines)
  end

  @doc """
  Patches `signals` into the client-side signal store.
  """
  def patch_signals(conn, signals, opts \\ []) do
    lines = data("onlyIfMissing", opts[:only_if_missing]) ++ data("signals", encode(signals))

    frame(conn, "datastar-patch-signals", lines)
  end

  @doc """
  Writes a comment frame. Proxies keep an idle connection open for it, and it
  is how a browser that has gone away is noticed, since nothing else writes.
  """
  def keepalive(conn), do: chunk(conn, ": keepalive\n\n")

  @doc """
  Blocks handing each received message to `handler`, which emits frames and
  answers `{:cont, conn}` or `{:halt, conn}`. Idle connections get a keepalive
  comment, which is also how a browser that has gone away is noticed.
  """
  def stream(conn, handler, opts \\ []) when is_function(handler, 2) do
    keepalive_ms = Keyword.get(opts, :keepalive_ms, @keepalive_ms)

    receive do
      message ->
        case handler.(message, conn) do
          {:cont, conn} -> stream(conn, handler, opts)
          {:halt, conn} -> conn
        end
    after
      keepalive_ms ->
        case keepalive(conn) do
          {:ok, conn} -> stream(conn, handler, opts)
          {:error, _reason} -> conn
        end
    end
  end

  defp frame(conn, event, lines) do
    chunk(conn, Enum.join(["event: " <> event | lines] ++ ["", ""], "\n"))
  end

  defp data(_name, nil), do: []

  defp data(name, value) do
    value
    |> to_string()
    |> String.split("\n")
    |> Enum.map(&"data: #{name} #{&1}")
  end

  defp encode(signals), do: Jason.encode!(signals)
end
