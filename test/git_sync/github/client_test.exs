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

  test "follows pagination until a short page comes back" do
    stub(fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["per_page"] == "50"

      case conn.query_params["page"] do
        "1" -> Req.Test.json(conn, Enum.map(1..50, &github_repo("adam/repo-#{&1}")))
        "2" -> Req.Test.json(conn, [github_repo("adam/zulu")])
      end
    end)

    assert {:ok, repos} = Client.list_repos(@connection)
    assert length(repos) == 51
    assert List.last(repos).full_name == "adam/zulu"
  end

  test "omits archived repositories" do
    stub(fn conn ->
      Req.Test.json(conn, [
        github_repo("adam/git-sync"),
        Map.put(github_repo("adam/retired"), "archived", true)
      ])
    end)

    assert {:ok, [%{full_name: "adam/git-sync"}]} = Client.list_repos(@connection)
  end

  test "reports a connection that has not been authorized yet" do
    assert {:error, "Connect GitHub to list its repositories"} =
             Client.list_repos(%Connection{base_url: "https://github.com"})
  end

  test "reports an unauthorized response" do
    stub(fn conn -> Plug.Conn.send_resp(conn, 401, "") end)

    assert {:error, "GitHub returned HTTP 401"} = Client.list_repos(@connection)
  end

  defp github_repo(full_name) do
    %{
      "full_name" => full_name,
      "clone_url" => "https://github.com/#{full_name}.git",
      "private" => true,
      "archived" => false
    }
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

  describe "check/1" do
    test "asks for the account behind the token and nothing more" do
      stub(fn conn ->
        assert conn.host == "api.github.com"
        assert conn.request_path == "/user"
        assert ["Bearer gho_tok"] = Plug.Conn.get_req_header(conn, "authorization")

        Req.Test.json(conn, %{"login" => "adam"})
      end)

      assert Client.check(@connection) == :ok
    end

    test "reports the status when the account cannot be read" do
      stub(&Plug.Conn.send_resp(&1, 401, ""))

      assert Client.check(@connection) == {:error, "GitHub returned HTTP 401"}
    end

    test "says so when there is no token to check with" do
      assert {:error, message} = Client.check(%Connection{base_url: "https://github.com"})
      assert message =~ "Connect GitHub"
    end
  end
end
