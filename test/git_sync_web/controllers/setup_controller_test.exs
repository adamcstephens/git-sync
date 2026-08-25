defmodule GitSyncWeb.SetupControllerTest do
  use GitSyncWeb.ConnCase

  alias GitSync.Connections

  @document %{
    "issuer" => "https://forge.test",
    "authorization_endpoint" => "https://forge.test/login/oauth/authorize",
    "token_endpoint" => "https://forge.test/login/oauth/access_token",
    "userinfo_endpoint" => "https://forge.test/login/oauth/userinfo"
  }

  @params %{
    "base_url" => "https://forge.test",
    "client_id" => "abc",
    "client_secret" => "shh"
  }

  test "an unconfigured app sends every route to the wizard", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/")) == ~p"/setup"
    assert redirected_to(get(conn, ~p"/login")) == ~p"/setup"
  end

  test "GET /setup renders the form", %{conn: conn} do
    assert html_response(get(conn, ~p"/setup"), 200) =~ "Forgejo URL"
  end

  test "POST /setup saves the instance once discovery succeeds", %{conn: conn} do
    Req.Test.stub(GitSync.Http, &Req.Test.json(&1, @document))

    conn = post(conn, ~p"/setup", connection: @params)

    assert redirected_to(conn) == ~p"/login"
    assert Connections.configured?()
    assert Connections.forgejo().client_secret == "shh"
  end

  test "POST /setup saves nothing when discovery fails", %{conn: conn} do
    Req.Test.stub(GitSync.Http, &Plug.Conn.send_resp(&1, 404, ""))

    conn = post(conn, ~p"/setup", connection: @params)

    assert html_response(conn, 200) =~ "Could not reach that Forgejo instance"
    refute Connections.configured?()
  end

  test "POST /setup rejects an incomplete form", %{conn: conn} do
    Req.Test.stub(GitSync.Http, &Req.Test.json(&1, @document))

    conn = post(conn, ~p"/setup", connection: %{@params | "client_id" => ""})

    assert html_response(conn, 200) =~ "can&#39;t be blank"
    refute Connections.configured?()
  end

  test "the wizard closes once the app is configured", %{conn: conn} do
    {:ok, _connection} = Connections.configure_forgejo(@params)

    assert redirected_to(get(conn, ~p"/setup")) == ~p"/"
  end
end
