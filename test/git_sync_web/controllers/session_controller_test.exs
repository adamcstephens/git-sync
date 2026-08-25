defmodule GitSyncWeb.SessionControllerTest do
  use GitSyncWeb.ConnCase

  test "GET /login renders the sign-in page", %{conn: conn} do
    conn = get(conn, ~p"/login")
    assert html_response(conn, 200) =~ "Sign in with Forgejo"
  end

  test "DELETE /logout clears the session", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{"operator" => "alice"})
      |> delete(~p"/logout")

    assert redirected_to(conn) == ~p"/login"
    refute get_session(conn, "operator")
  end
end
