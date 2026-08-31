defmodule GitSyncWeb.SessionControllerTest do
  use GitSyncWeb.ConnCase

  alias GitSync.Connections
  alias GitSync.Forge.Token
  alias GitSync.Forgejo.Provider
  alias GitSync.OidcProvider

  setup :configure_forgejo

  test "GET /login renders the sign-in page", %{conn: conn} do
    conn = get(conn, ~p"/login")
    assert html_response(conn, 200) =~ "Sign in with Forgejo"
  end

  test "the page does not offer a Forgejo that cannot be an issuer", %{
    conn: conn,
    connection: connection
  } do
    connection
    |> Ecto.Changeset.change(base_url: "file:///srv/dev_repos/forgejo")
    |> GitSync.Repo.update!()

    conn = get(conn, ~p"/login")

    refute html_response(conn, 200) =~ "Sign in with Forgejo"
  end

  describe "with a live provider" do
    setup %{connection: connection} do
      issuer = OidcProvider.start(subject: "alice", client_id: connection.client_id)

      :ok = Provider.stop()
      on_exit(&Provider.stop/0)

      start_supervised!(
        {Oidcc.ProviderConfiguration.Worker,
         %{
           issuer: issuer,
           name: Provider.name(),
           provider_configuration_opts: %{quirks: %{allow_unsafe_http: true}}
         }}
      )

      :ok
    end

    test "the authorization request carries an S256 PKCE challenge", %{conn: conn} do
      conn = post(conn, ~p"/auth/forgejo")

      %{query: query} = conn |> redirected_to(302) |> URI.parse()
      params = URI.decode_query(query)

      assert params["code_challenge_method"] == "S256"
      assert byte_size(params["code_challenge"]) > 0
    end

    test "the redirect URI follows the host the operator is using", %{conn: conn} do
      for host <- ["localhost", "kale.v.robins.wtf"] do
        params =
          %{conn | host: host}
          |> post(~p"/auth/forgejo")
          |> redirected_to(302)
          |> URI.parse()
          |> Map.fetch!(:query)
          |> URI.decode_query()

        assert params["redirect_uri"] == "http://#{host}/auth/forgejo/callback"
      end
    end

    test "a full code flow claims the operator seat and stores the token", %{conn: conn} do
      conn = sign_in(conn)

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, "operator") == "alice"

      connection = Connections.forgejo()
      assert connection.operator == "alice"
      assert connection.token == "forgejo-access-token"
      assert connection.refresh_token == "forgejo-refresh-token"
      assert DateTime.diff(connection.token_expires_at, DateTime.utc_now()) > 3500
    end

    test "the token request proves possession of the PKCE verifier", %{conn: conn} do
      sign_in(conn)

      verifier = OidcProvider.code_verifier()

      assert Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false) ==
               OidcProvider.code_challenge()
    end

    test "a second Forgejo user is refused", %{conn: conn, connection: connection} do
      {:ok, _connection} =
        Connections.record_login(connection, "bob", Token.new("bobs-token", nil, nil))

      conn = sign_in(conn)

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "already claimed by bob"
      refute get_session(conn, "operator")
    end
  end

  test "the callback refuses a code with no authorization session", %{conn: conn} do
    conn = get(conn, ~p"/auth/forgejo/callback", %{"code" => "c", "state" => "s"})

    assert redirected_to(conn) == ~p"/login"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "missing_authorize_session"
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

  defp sign_in(conn) do
    conn = post(conn, ~p"/auth/forgejo")

    callback =
      conn
      |> redirected_to(302)
      |> Req.get!(redirect: false)
      |> Req.Response.get_header("location")
      |> List.first()
      |> URI.parse()

    conn
    |> recycle()
    |> Map.put(:secret_key_base, conn.secret_key_base)
    |> get(callback.path <> "?" <> callback.query)
  end
end
