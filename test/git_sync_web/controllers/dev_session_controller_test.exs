defmodule GitSyncWeb.DevSessionControllerTest do
  use GitSyncWeb.ConnCase

  alias GitSync.Connections

  setup :configure_forgejo

  test "GET /dev/login claims the seat and signs the operator in", %{conn: conn} do
    conn = get(conn, ~p"/dev/login")

    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, "operator") == "dev"
    assert %{operator: "dev"} = Connections.forgejo()
  end

  test "signing in twice does not trip the seat claim", %{conn: conn} do
    conn |> get(~p"/dev/login") |> recycle()

    conn = get(conn, ~p"/dev/login")

    assert redirected_to(conn) == ~p"/"
  end

  test "the sign-in page offers the bypass", %{conn: conn} do
    conn = get(conn, ~p"/login")

    assert html_response(conn, 200) =~ ~p"/dev/login"
  end
end
