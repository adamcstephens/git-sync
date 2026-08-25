defmodule GitSyncWeb.ConnectionControllerTest do
  use GitSyncWeb.ConnCase

  setup :configure_forgejo

  setup %{conn: conn, connection: connection} do
    {:ok, _connection} = GitSync.Connections.record_login(connection, "alice", "tok")

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
end
