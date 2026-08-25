defmodule GitSyncWeb.PageControllerTest do
  use GitSyncWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "git-sync"
  end
end
