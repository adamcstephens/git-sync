defmodule GitSyncWeb.ConnectionControllerTest do
  use GitSyncWeb.ConnCase

  alias GitSync.Forge.Token

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

  test "offers a form to configure a Tangled knot", %{conn: conn} do
    Req.Test.stub(GitSync.Http, &Plug.Conn.send_resp(&1, 401, ""))

    html = html_response(get(conn, ~p"/connections"), 200)

    assert html =~ "tangled-form"
    refute html =~ "Could not list Tangled repositories"
  end

  test "saving a knot stores the connection", %{conn: conn} do
    conn =
      post(conn, ~p"/connections/tangled", %{
        "connection" => %{
          "base_url" => "https://knot.example.com",
          "ssh_key" => "-----BEGIN OPENSSH PRIVATE KEY-----",
          "host_key" => "knot.example.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIexample"
        }
      })

    assert redirected_to(conn) == ~p"/connections"
    assert GitSync.Connections.tangled().base_url == "https://knot.example.com"
  end

  test "re-renders the page when the knot details are incomplete", %{conn: conn} do
    Req.Test.stub(GitSync.Http, &Plug.Conn.send_resp(&1, 401, ""))

    conn = post(conn, ~p"/connections/tangled", %{"connection" => %{"base_url" => ""}})

    assert html_response(conn, 200) =~ "can&#39;t be blank"
    refute GitSync.Connections.tangled()
  end
end
