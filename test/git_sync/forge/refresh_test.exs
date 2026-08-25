defmodule GitSync.Forge.RefreshTest do
  use GitSync.DataCase

  alias GitSync.Connections
  alias GitSync.Forge
  alias GitSync.Forge.Token

  defp github(token) do
    {:ok, connection} =
      Connections.enable_github(%{"client_id" => "cid", "client_secret" => "secret"})

    {:ok, connection} = Connections.store_token(connection, token)
    connection
  end

  defp stub(fun), do: Req.Test.stub(GitSync.Http, fun)

  test "a live token is used as it stands" do
    connection = github(Token.new("gho_live", "ghr_ref", 3600))

    assert {:ok, ^connection} = Forge.fresh(connection)
  end

  test "a spent token is renewed and the new pair written back" do
    connection = github(Token.new("gho_spent", "ghr_ref", 10))

    stub(fn conn ->
      assert conn.request_path == "/login/oauth/access_token"
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert %{
               "grant_type" => "refresh_token",
               "refresh_token" => "ghr_ref",
               "client_id" => "cid",
               "client_secret" => "secret"
             } = URI.decode_query(body)

      Req.Test.json(conn, %{
        "access_token" => "gho_new",
        "refresh_token" => "ghr_new",
        "expires_in" => 28_800
      })
    end)

    assert {:ok, refreshed} = Forge.fresh(connection)
    assert refreshed.token == "gho_new"

    assert %{token: "gho_new", refresh_token: "ghr_new"} = Connections.github()
    assert DateTime.diff(Connections.github().token_expires_at, DateTime.utc_now()) > 28_000
  end

  test "a spent token with no refresh token asks for a reconnection" do
    connection = github(Token.new("gho_spent", nil, 10))

    assert {:error, "GitHub must be reconnected" <> _} = Forge.fresh(connection)
  end

  test "a refusal from the forge is reported rather than swallowed" do
    connection = github(Token.new("gho_spent", "ghr_expired", 10))

    stub(fn conn ->
      Req.Test.json(conn, %{
        "error" => "bad_refresh_token",
        "error_description" => "The refresh token passed is expired."
      })
    end)

    assert {:error, "The refresh token passed is expired."} = Forge.fresh(connection)
  end

  test "the calls that need a credential go through the refresh" do
    connection = github(Token.new("gho_spent", nil, 10))

    assert {:error, "GitHub must be reconnected" <> _} = Forge.list_repos(connection)

    assert {:error, "GitHub must be reconnected" <> _} =
             Forge.create_webhook(connection, "adam/git-sync", "https://sync.test/hooks/1", "shh")
  end

  test "a connection nobody has signed in to is left alone" do
    connection = github(nil)

    assert {:ok, ^connection} = Forge.fresh(connection)
  end
end
