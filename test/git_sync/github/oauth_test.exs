defmodule GitSync.Github.OAuthTest do
  use ExUnit.Case, async: true

  alias GitSync.Connection
  alias GitSync.Forge.Token
  alias GitSync.Github.OAuth

  @connection %Connection{
    base_url: "https://github.com",
    client_id: "cid",
    client_secret: "secret"
  }

  defp stub(fun), do: Req.Test.stub(GitSync.Http, fun)

  test "sends the operator to GitHub with a state parameter" do
    url = OAuth.authorize_url(@connection, "https://sync.test/auth/github/callback", "st4te")

    assert %URI{host: "github.com", path: "/login/oauth/authorize", query: query} = URI.parse(url)

    assert %{
             "client_id" => "cid",
             "redirect_uri" => "https://sync.test/auth/github/callback",
             "state" => "st4te",
             "scope" => scope
           } = URI.decode_query(query)

    assert scope =~ "repo"
  end

  test "states are unguessable and unique" do
    assert byte_size(OAuth.state()) >= 16
    refute OAuth.state() == OAuth.state()
  end

  test "exchanges the code for a token" do
    stub(fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/login/oauth/access_token"
      assert ["application/json"] = Plug.Conn.get_req_header(conn, "accept")

      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert %{
               "client_id" => "cid",
               "client_secret" => "secret",
               "code" => "the-code",
               "redirect_uri" => "https://sync.test/auth/github/callback"
             } = URI.decode_query(body)

      Req.Test.json(conn, %{
        "access_token" => "gho_tok",
        "token_type" => "bearer",
        "refresh_token" => "ghr_tok",
        "expires_in" => 28_800
      })
    end)

    assert {:ok, %Token{access: "gho_tok", refresh: "ghr_tok", expires_at: %DateTime{}}} =
             OAuth.exchange_code(
               @connection,
               "the-code",
               "https://sync.test/auth/github/callback"
             )
  end

  test "renews an expiring token with the refresh token" do
    stub(fn conn ->
      assert conn.request_path == "/login/oauth/access_token"
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert %{
               "client_id" => "cid",
               "client_secret" => "secret",
               "grant_type" => "refresh_token",
               "refresh_token" => "ghr_old"
             } = URI.decode_query(body)

      Req.Test.json(conn, %{
        "access_token" => "gho_new",
        "refresh_token" => "ghr_new",
        "expires_in" => 28_800
      })
    end)

    assert {:ok, %Token{access: "gho_new", refresh: "ghr_new"}} =
             OAuth.refresh(%{@connection | refresh_token: "ghr_old"})
  end

  test "reports the error GitHub describes" do
    stub(fn conn ->
      Req.Test.json(conn, %{
        "error" => "bad_verification_code",
        "error_description" => "The code passed is incorrect or expired."
      })
    end)

    assert {:error, "The code passed is incorrect or expired."} =
             OAuth.exchange_code(@connection, "stale", "https://sync.test/auth/github/callback")
  end

  test "reports an unexpected status" do
    stub(fn conn -> Plug.Conn.send_resp(conn, 500, "") end)

    assert {:error, "GitHub returned HTTP 500"} =
             OAuth.exchange_code(
               @connection,
               "the-code",
               "https://sync.test/auth/github/callback"
             )
  end
end
