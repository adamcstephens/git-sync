defmodule GitSync.Pushin.ClientTest do
  use ExUnit.Case, async: true

  alias GitSync.Connection
  alias GitSync.Pushin.Client

  @connection %Connection{kind: :pushin, base_url: "https://pushin.eu", token: "pat"}

  defp stub(fun), do: Req.Test.stub(GitSync.Http, fun)

  test "lists repositories with string IDs and preserves visibility and clone URLs" do
    stub(fn conn ->
      assert conn.method == "GET"
      assert conn.host == "pushin.eu"
      assert conn.request_path == "/api/v1/user/repos"
      assert ["Bearer pat"] = Plug.Conn.get_req_header(conn, "authorization")

      Req.Test.json(conn, [
        pushin_repo("adam/git-sync"),
        Map.put(pushin_repo("adam/private"), "private", true),
        Map.put(pushin_repo("adam/retired"), "archived", true)
      ])
    end)

    assert {:ok,
            [
              %{
                full_name: "adam/git-sync",
                clone_url: "https://git.pushin.eu/adam/git-sync.git",
                private: false
              },
              %{
                full_name: "adam/private",
                clone_url: "https://git.pushin.eu/adam/private.git",
                private: true
              }
            ]} = Client.list_repos(@connection)
  end

  test "continues past a full archived page and stops at the first short page" do
    stub(fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["per_page"] == "50"
      refute Map.has_key?(conn.query_params, "limit")

      case conn.query_params["page"] do
        "1" ->
          repos = Enum.map(1..50, &Map.put(pushin_repo("adam/repo-#{&1}"), "archived", true))
          Req.Test.json(conn, repos)

        "2" ->
          Req.Test.json(conn, [pushin_repo("adam/active")])
      end
    end)

    assert {:ok, [%{full_name: "adam/active"}]} = Client.list_repos(@connection)
  end

  test "does not return a partial repository list when a later page is unauthorized" do
    stub(fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      case conn.query_params["page"] do
        "1" -> Req.Test.json(conn, Enum.map(1..50, &pushin_repo("adam/repo-#{&1}")))
        "2" -> Plug.Conn.send_resp(conn, 401, "")
      end
    end)

    assert {:error, _reason} = Client.list_repos(@connection)
  end

  test "checks the account with the PAT rather than listing repositories" do
    stub(fn conn ->
      assert conn.method == "GET"
      assert conn.host == "pushin.eu"
      assert conn.request_path == "/api/v1/user"
      assert ["Bearer pat"] = Plug.Conn.get_req_header(conn, "authorization")
      Req.Test.json(conn, %{"id" => "user-123", "username" => "adam"})
    end)

    assert :ok = Client.check(@connection)
  end

  test "rejects unauthorized credentials for both account checks and repository listing" do
    stub(&Plug.Conn.send_resp(&1, 401, ""))

    assert {:error, _reason} = Client.check(@connection)
    assert {:error, _reason} = Client.list_repos(@connection)
  end

  test "requires a token before making an API request" do
    stub(fn _conn -> flunk("a missing token must not reach the API") end)

    for token <- [nil, ""] do
      connection = %Connection{@connection | token: token}
      assert {:error, _reason} = Client.check(connection)
      assert {:error, _reason} = Client.list_repos(connection)
    end
  end

  test "uses the separate HTTPS Git host with a .git suffix for reads and writes" do
    for mode <- [:read, :write] do
      assert Client.clone_url(@connection, "adam/git-sync", mode) ==
               "https://git.pushin.eu/adam/git-sync.git"
    end
  end

  test "rejects unsupported webhooks and PAT refresh without making API requests" do
    stub(fn _conn -> flunk("unsupported operations must not reach the API") end)

    assert {:error, :unsupported} =
             Client.create_webhook(
               @connection,
               "adam/git-sync",
               "https://sync.example/hook",
               "secret"
             )

    assert {:error, :unsupported} = Client.verify_webhook(@connection, [], "{}", "secret")
    assert {:error, :unsupported} = Client.refresh(@connection)
  end

  defp pushin_repo(full_name) do
    %{
      "id" => "repo-#{full_name}",
      "full_name" => full_name,
      "clone_url" => "https://git.pushin.eu/#{full_name}.git",
      "private" => false
    }
  end
end
