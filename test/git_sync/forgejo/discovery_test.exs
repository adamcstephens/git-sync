defmodule GitSync.Forgejo.DiscoveryTest do
  use ExUnit.Case, async: true

  alias GitSync.Forgejo.Discovery

  @document %{
    "issuer" => "https://codeberg.org/",
    "authorization_endpoint" => "https://codeberg.org/login/oauth/authorize",
    "token_endpoint" => "https://codeberg.org/login/oauth/access_token",
    "userinfo_endpoint" => "https://codeberg.org/login/oauth/userinfo"
  }

  defp stub(fun), do: Req.Test.stub(GitSync.Http, fun)

  test "accepts a complete discovery document" do
    stub(fn conn ->
      assert conn.request_path == "/.well-known/openid-configuration"
      Req.Test.json(conn, @document)
    end)

    assert {:ok, %{"issuer" => "https://codeberg.org/"}} =
             Discovery.fetch("https://codeberg.org/")
  end

  test "rejects a document missing endpoints" do
    stub(fn conn -> Req.Test.json(conn, Map.delete(@document, "token_endpoint")) end)

    assert {:error, message} = Discovery.fetch("https://codeberg.org")
    assert message =~ "token_endpoint"
  end

  test "reports a non-200 response" do
    stub(fn conn -> Plug.Conn.send_resp(conn, 404, "") end)

    assert {:error, "discovery returned HTTP 404"} = Discovery.fetch("https://example.com")
  end
end
