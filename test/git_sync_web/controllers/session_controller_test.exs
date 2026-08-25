defmodule GitSyncWeb.SessionControllerTest do
  use GitSyncWeb.ConnCase

  setup :configure_forgejo

  test "GET /login renders the sign-in page", %{conn: conn} do
    conn = get(conn, ~p"/login")
    assert html_response(conn, 200) =~ "Sign in with Forgejo"
  end

  test "the callback refuses a state that does not match the session", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{"oidc_state" => "expected"})
      |> get(~p"/auth/forgejo/callback", %{"code" => "c", "state" => "forged"})

    assert redirected_to(conn) == ~p"/login"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "state_mismatch"
  end

  test "the callback refuses a request Forgejo denied", %{conn: conn} do
    conn = get(conn, ~p"/auth/forgejo/callback", %{"error" => "access_denied"})

    assert redirected_to(conn) == ~p"/login"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "no_code"
  end

  test "DELETE /logout clears the session", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{"operator" => "alice"})
      |> delete(~p"/logout")

    assert redirected_to(conn) == ~p"/login"
    refute get_session(conn, "operator")
  end

  test "signed-out visitors are sent to the login page", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/")) == ~p"/login"
    assert redirected_to(get(conn, ~p"/connections")) == ~p"/login"
  end
end
