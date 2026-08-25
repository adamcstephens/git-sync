defmodule GitSyncWeb.SSETest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias GitSyncWeb.SSE

  defp open do
    :get |> conn("/") |> SSE.open()
  end

  describe "open/1" do
    test "sends event-stream headers" do
      conn = open()

      assert conn.state == :chunked
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/event-stream"]
      assert get_resp_header(conn, "cache-control") == ["no-cache"]
    end
  end

  describe "patch_elements/3" do
    test "emits an elements frame" do
      {:ok, conn} = SSE.patch_elements(open(), "<div>Merge</div>")

      assert conn.resp_body == """
             event: datastar-patch-elements
             data: elements <div>Merge</div>

             """
    end

    test "emits one data line per line of markup" do
      {:ok, conn} = SSE.patch_elements(open(), "<div>\n  <span>Merge</span>\n</div>")

      assert conn.resp_body == """
             event: datastar-patch-elements
             data: elements <div>
             data: elements   <span>Merge</span>
             data: elements </div>

             """
    end

    test "emits selector and mode when given" do
      {:ok, conn} =
        SSE.patch_elements(open(), "<div>Merge</div>", selector: "div", mode: :append)

      assert conn.resp_body == """
             event: datastar-patch-elements
             data: selector div
             data: mode append
             data: elements <div>Merge</div>

             """
    end

    test "emits a frame with no elements when removing" do
      {:ok, conn} = SSE.patch_elements(open(), nil, selector: "#target", mode: :remove)

      assert conn.resp_body == """
             event: datastar-patch-elements
             data: selector #target
             data: mode remove

             """
    end

    test "appends successive frames" do
      {:ok, conn} = SSE.patch_elements(open(), "<div>One</div>")
      {:ok, conn} = SSE.patch_elements(conn, "<div>Two</div>")

      assert conn.resp_body == """
             event: datastar-patch-elements
             data: elements <div>One</div>

             event: datastar-patch-elements
             data: elements <div>Two</div>

             """
    end
  end

  describe "patch_signals/3" do
    test "emits a signals frame" do
      {:ok, conn} = SSE.patch_signals(open(), %{one: 1, two: 2})

      assert conn.resp_body == """
             event: datastar-patch-signals
             data: signals {"one":1,"two":2}

             """
    end

    test "emits onlyIfMissing when given" do
      {:ok, conn} = SSE.patch_signals(open(), %{one: 1}, only_if_missing: true)

      assert conn.resp_body == """
             event: datastar-patch-signals
             data: onlyIfMissing true
             data: signals {"one":1}

             """
    end
  end

  describe "stream/3" do
    test "hands each message to the handler until it halts" do
      send(self(), {:frame, "<div>One</div>"})
      send(self(), {:frame, "<div>Two</div>"})
      send(self(), :done)

      conn =
        SSE.stream(open(), fn
          {:frame, html}, conn ->
            {:ok, conn} = SSE.patch_elements(conn, html)
            {:cont, conn}

          :done, conn ->
            {:halt, conn}
        end)

      assert conn.resp_body == """
             event: datastar-patch-elements
             data: elements <div>One</div>

             event: datastar-patch-elements
             data: elements <div>Two</div>

             """
    end

    test "keeps an idle connection open" do
      {:ok, conn} = SSE.keepalive(open())

      assert conn.resp_body == ": keepalive\n\n"
    end
  end
end
