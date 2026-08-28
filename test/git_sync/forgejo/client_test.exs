defmodule GitSync.Forgejo.ClientTest do
  use ExUnit.Case, async: true

  alias GitSync.Connection
  alias GitSync.Forgejo.Client

  @connection %Connection{base_url: "https://codeberg.org/", token: "tok"}

  defp stub(fun), do: Req.Test.stub(GitSync.Http, fun)

  test "lists the operator's repositories" do
    stub(fn conn ->
      assert conn.request_path == "/api/v1/user/repos"
      assert ["Bearer tok"] = Plug.Conn.get_req_header(conn, "authorization")

      Req.Test.json(conn, [
        %{
          "full_name" => "adam/git-sync",
          "clone_url" => "https://codeberg.org/adam/git-sync.git",
          "private" => false
        }
      ])
    end)

    assert {:ok, [%{full_name: "adam/git-sync", private: false}]} = Client.list_repos(@connection)
  end

  test "follows pagination until a short page comes back" do
    stub(fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["limit"] == "50"

      case conn.query_params["page"] do
        "1" -> Req.Test.json(conn, Enum.map(1..50, &forgejo_repo("adam/repo-#{&1}")))
        "2" -> Req.Test.json(conn, [forgejo_repo("adam/zulu")])
      end
    end)

    assert {:ok, repos} = Client.list_repos(@connection)
    assert length(repos) == 51
    assert List.last(repos).full_name == "adam/zulu"
  end

  test "omits archived repositories" do
    stub(fn conn ->
      Req.Test.json(conn, [
        forgejo_repo("adam/git-sync"),
        Map.put(forgejo_repo("adam/retired"), "archived", true)
      ])
    end)

    assert {:ok, [%{full_name: "adam/git-sync"}]} = Client.list_repos(@connection)
  end

  test "reports a connection that has not been authorized yet" do
    assert {:error, "Connect Forgejo to list its repositories"} =
             Client.list_repos(%Connection{base_url: "https://codeberg.org/"})
  end

  test "reports an unauthorized response" do
    stub(fn conn -> Plug.Conn.send_resp(conn, 401, "") end)

    assert {:error, "Forgejo returned HTTP 401"} = Client.list_repos(@connection)
  end

  defp forgejo_repo(full_name) do
    %{
      "full_name" => full_name,
      "clone_url" => "https://codeberg.org/#{full_name}.git",
      "private" => false,
      "archived" => false
    }
  end

  describe "clone_url/3" do
    test "joins the repository onto the instance base url" do
      assert Client.clone_url(@connection, "adam/git-sync", :read) ==
               "https://codeberg.org/adam/git-sync"
    end
  end

  describe "create_webhook/4" do
    test "registers a push webhook on the repository" do
      stub(fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/api/v1/repos/adam/git-sync/hooks"
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert %{
                 "type" => "forgejo",
                 "events" => ["push"],
                 "config" => %{"url" => "https://sync.example/hooks/1", "secret" => "shh"}
               } = JSON.decode!(body)

        conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{"id" => 7})
      end)

      assert {:ok, 7} =
               Client.create_webhook(
                 @connection,
                 "adam/git-sync",
                 "https://sync.example/hooks/1",
                 "shh"
               )
    end

    test "reports a rejected registration" do
      stub(fn conn -> Plug.Conn.send_resp(conn, 403, "") end)

      assert {:error, "Forgejo returned HTTP 403"} =
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
      headers = [{"x-forgejo-signature", signature(body, "shh")}]

      assert :ok = Client.verify_webhook(@connection, headers, body, "shh")
    end

    test "accepts the gitea-compatible header" do
      body = ~s({"ref":"refs/heads/main"})
      headers = [{"x-gitea-signature", signature(body, "shh")}]

      assert :ok = Client.verify_webhook(@connection, headers, body, "shh")
    end

    test "rejects a body signed with another secret" do
      body = ~s({"ref":"refs/heads/main"})
      headers = [{"x-forgejo-signature", signature(body, "other")}]

      assert {:error, :invalid_signature} =
               Client.verify_webhook(@connection, headers, body, "shh")
    end

    test "rejects an unsigned delivery" do
      assert {:error, :missing_signature} = Client.verify_webhook(@connection, [], "{}", "shh")
    end
  end

  defp signature(body, secret),
    do: Base.encode16(:crypto.mac(:hmac, :sha256, secret, body), case: :lower)
end
