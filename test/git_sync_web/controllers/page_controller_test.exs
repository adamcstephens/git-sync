defmodule GitSyncWeb.PageControllerTest do
  use GitSyncWeb.ConnCase

  setup :configure_forgejo

  test "GET / renders the dashboard for the operator", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{"operator" => "alice"})
      |> get(~p"/")

    assert html_response(conn, 200) =~ "git-sync"
  end

  test "GET / redirects anonymous visitors to the login page", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/login"
  end
end
