defmodule GitSyncWeb.ConnectionControllerTest do
  use GitSyncWeb.ConnCase

  alias GitSync.Connections
  alias GitSync.Forge.Token
  alias GitSync.KnotServer

  setup :configure_forgejo

  setup %{conn: conn, connection: connection} do
    {:ok, _connection} =
      GitSync.Connections.record_login(connection, "alice", Token.new("tok", nil, nil))

    %{conn: init_test_session(conn, %{"operator" => "alice"})}
  end

  test "shows the instance and its repositories", %{conn: conn} do
    Req.Test.stub(GitSync.Http, fn req_conn ->
      Req.Test.json(req_conn, [
        %{
          "full_name" => "alice/git-sync",
          "clone_url" => "https://forge.test/alice/git-sync.git",
          "private" => false
        }
      ])
    end)

    html = html_response(get(conn, ~p"/connections"), 200)

    assert html =~ "https://forge.test"
    assert html =~ "alice/git-sync"
  end

  test "reports why the repository list is unavailable", %{conn: conn} do
    Req.Test.stub(GitSync.Http, &Plug.Conn.send_resp(&1, 401, ""))

    assert html_response(get(conn, ~p"/connections"), 200) =~ "Could not list repositories"
  end

  describe "tangled" do
    setup %{conn: conn} do
      Req.Test.stub(GitSync.Http, &Plug.Conn.send_resp(&1, 401, ""))

      %{conn: conn, knot: KnotServer.serve()}
    end

    test "offers a form for the knot URL and nothing to paste", %{conn: conn} do
      html = html_response(get(conn, ~p"/connections"), 200)

      assert html =~ "tangled-form"
      refute html =~ "connection[ssh_key]"
      refute html =~ "connection[host_key]"
    end

    test "saving a knot scans it and shows the fingerprints", %{conn: conn, knot: knot} do
      saved = post(conn, ~p"/connections/tangled", %{"connection" => knot_params()})

      assert redirected_to(saved) == ~p"/connections"
      assert Connections.tangled().base_url == "https://127.0.0.1"

      assert html_response(get(conn, ~p"/connections"), 200) =~
               KnotServer.fingerprint(knot.public)
    end

    test "a knot that cannot be reached re-renders the page", %{conn: conn} do
      KnotServer.refuse()

      conn = post(conn, ~p"/connections/tangled", %{"connection" => knot_params()})

      assert html_response(conn, 200) =~ "no host keys came back"
      refute Connections.tangled()
    end

    test "generating a key shows the public half to copy", %{conn: conn} do
      post(conn, ~p"/connections/tangled", %{"connection" => knot_params()})

      generated = post(conn, ~p"/connections/tangled/key")

      assert redirected_to(generated) == ~p"/connections"

      html = html_response(get(conn, ~p"/connections"), 200)

      assert html =~ Connections.tangled().public_key
      refute html =~ "BEGIN OPENSSH PRIVATE KEY"
    end

    test "there is nothing to generate a key for until a knot is saved", %{conn: conn} do
      conn = post(conn, ~p"/connections/tangled/key")

      assert redirected_to(conn) == ~p"/connections"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "No knot"
    end
  end

  defp knot_params, do: %{"base_url" => "https://127.0.0.1"}
end
