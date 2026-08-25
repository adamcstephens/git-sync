defmodule GitSync.Github.ClientTest do
  use ExUnit.Case, async: true

  alias GitSync.Connection
  alias GitSync.Github.Client

  @connection %Connection{base_url: "https://github.com", token: "gho_tok"}

  defp stub(fun), do: Req.Test.stub(GitSync.Http, fun)

  test "lists the repositories the token can reach" do
    stub(fn conn ->
      assert conn.host == "api.github.com"
      assert conn.request_path == "/user/repos"
      assert ["Bearer gho_tok"] = Plug.Conn.get_req_header(conn, "authorization")

      Req.Test.json(conn, [
        %{
          "full_name" => "adam/git-sync",
          "clone_url" => "https://github.com/adam/git-sync.git",
          "private" => true
        }
      ])
    end)

    assert {:ok, [%{full_name: "adam/git-sync", private: true}]} = Client.list_repos(@connection)
  end

  test "reports an unauthorized response" do
    stub(fn conn -> Plug.Conn.send_resp(conn, 401, "") end)

    assert {:error, "GitHub returned HTTP 401"} = Client.list_repos(@connection)
  end

  describe "clone_url/3" do
    test "joins the repository onto github.com" do
      assert Client.clone_url(@connection, "adam/git-sync", :write) ==
               "https://github.com/adam/git-sync"
    end
  end

  describe "create_webhook/4" do
    test "registers a push webhook on the repository" do
      stub(fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/repos/adam/git-sync/hooks"
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert %{
                 "name" => "web",
                 "events" => ["push"],
                 "config" => %{"url" => "https://sync.example/hooks/1", "secret" => "shh"}
               } = JSON.decode!(body)

        conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{"id" => 12})
      end)

      assert {:ok, 12} =
               Client.create_webhook(
                 @connection,
                 "adam/git-sync",
                 "https://sync.example/hooks/1",
                 "shh"
               )
    end

    test "reports a rejected registration" do
      stub(fn conn -> Plug.Conn.send_resp(conn, 404, "") end)

      assert {:error, "GitHub returned HTTP 404"} =
               Client.create_webhook(
                 @connection,
                 "adam/git-sync",
                 "https://sync.example/hooks/1",
                 "shh"
               )
    end
  end

  describe "verify_webhook/4" do
    test "accepts a body matching the signature header" do
      body = ~s({"ref":"refs/heads/main"})
      headers = [{"x-hub-signature-256", signature(body, "shh")}]

      assert :ok = Client.verify_webhook(@connection, headers, body, "shh")
    end

    test "rejects a body signed with another secret" do
      body = ~s({"ref":"refs/heads/main"})
      headers = [{"x-hub-signature-256", signature(body, "other")}]

      assert {:error, :invalid_signature} =
               Client.verify_webhook(@connection, headers, body, "shh")
    end

    test "rejects an unsigned delivery" do
      assert {:error, :missing_signature} = Client.verify_webhook(@connection, [], "{}", "shh")
    end
  end

  defp signature(body, secret),
    do: "sha256=" <> Base.encode16(:crypto.mac(:hmac, :sha256, secret, body), case: :lower)
end
