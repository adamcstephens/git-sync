defmodule GitSync.Tangled.ClientTest do
  use ExUnit.Case, async: true

  alias GitSync.Connection
  alias GitSync.Tangled.Client

  @connection %Connection{kind: :tangled, base_url: "https://knot.example/"}

  @account %Connection{
    kind: :tangled,
    base_url: "https://tangled.org",
    did: "did:plc:abc",
    handle: "oppi.li",
    pds_url: "https://pds.example"
  }

  defp stub(fun), do: Req.Test.stub(GitSync.Http, fun)

  defp record(name, knot),
    do: %{
      "uri" => "at://did:plc:abc/sh.tangled.repo/#{name}",
      "value" => %{"$type" => "sh.tangled.repo", "knot" => knot}
    }

  describe "list_repos/1" do
    test "lists the repository records the account owns" do
      stub(fn conn ->
        assert conn.host == "pds.example"
        assert conn.request_path == "/xrpc/com.atproto.repo.listRecords"

        conn = Plug.Conn.fetch_query_params(conn)

        assert conn.query_params["repo"] == "did:plc:abc"
        assert conn.query_params["collection"] == "sh.tangled.repo"

        Req.Test.json(conn, %{"records" => [record("git-sync", "knot1.tangled.sh")]})
      end)

      assert {:ok, [repo]} = Client.list_repos(@account)

      assert repo == %{
               full_name: "knot1.tangled.sh/oppi.li/git-sync",
               clone_url: "https://tangled.org/oppi.li/git-sync",
               private: false
             }
    end

    test "follows the cursor until the records run out" do
      stub(fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        case conn.query_params["cursor"] do
          nil ->
            Req.Test.json(conn, %{
              "records" => [record("first", "knot1.tangled.sh")],
              "cursor" => "3m37uwfvtlp22"
            })

          "3m37uwfvtlp22" ->
            Req.Test.json(conn, %{"records" => [record("last", "knot1.tangled.sh")]})
        end
      end)

      assert {:ok, repos} = Client.list_repos(@account)

      assert Enum.map(repos, & &1.full_name) == [
               "knot1.tangled.sh/oppi.li/first",
               "knot1.tangled.sh/oppi.li/last"
             ]
    end

    test "omits repositories on knots nothing outside the operator's machine can reach" do
      stub(fn conn ->
        Req.Test.json(conn, %{
          "records" => [
            record("shipped", "knot1.tangled.sh"),
            record("scratch", "localhost:6444"),
            record("laptop", "orion.local:5555"),
            record("lan", "192.168.1.20:5555")
          ]
        })
      end)

      assert {:ok, repos} = Client.list_repos(@account)

      assert Enum.map(repos, & &1.full_name) == ["knot1.tangled.sh/oppi.li/shipped"]
    end

    test "drops the port a knot serves git over, which is not the port it is pushed to" do
      stub(fn conn ->
        Req.Test.json(conn, %{"records" => [record("git-sync", "knot.example.com:5555")]})
      end)

      assert {:ok, [%{full_name: "knot.example.com/oppi.li/git-sync"}]} =
               Client.list_repos(@account)
    end

    test "asks for an account that predates identity resolution to be saved again" do
      assert {:error, "Save the Tangled account again to list its repositories"} =
               Client.list_repos(@connection)
    end

    test "reports a repository server that will not answer" do
      stub(fn conn -> Plug.Conn.send_resp(conn, 502, "") end)

      assert {:error, "The repository server returned HTTP 502"} = Client.list_repos(@account)
    end
  end

  test "reads over https" do
    assert Client.clone_url(@connection, "adam/git-sync", :read) ==
             "https://knot.example/adam/git-sync"
  end

  test "writes over ssh as the knot's git user" do
    assert Client.clone_url(@connection, "adam/git-sync", :write) ==
             "git@knot.example:adam/git-sync"
  end

  test "reads a repo on another knot through the appview all the same" do
    assert Client.clone_url(@connection, "git.example.com/adam/git-sync", :read) ==
             "https://knot.example/adam/git-sync"
  end

  test "writes a repo on another knot straight to that knot" do
    assert Client.clone_url(@connection, "git.example.com/adam/git-sync", :write) ==
             "git@git.example.com:adam/git-sync"
  end

  test "names the knot a repo lives on" do
    assert Client.knot_host(@connection, "git.example.com/adam/git-sync") == "git.example.com"
    assert Client.knot_host(@connection, "adam/git-sync") == nil
  end

  test "falls back to the timer instead of webhooks" do
    assert {:error, :unsupported} =
             Client.create_webhook(@connection, "adam/git-sync", "https://s.example/h", "shh")

    assert {:error, :unsupported} = Client.verify_webhook(@connection, [], "{}", "shh")
  end

  describe "check/1" do
    test "describes the account's repository and nothing more" do
      stub(fn conn ->
        assert conn.host == "pds.example"
        assert conn.request_path == "/xrpc/com.atproto.repo.describeRepo"

        Req.Test.json(conn, %{"did" => "did:plc:abc"})
      end)

      assert Client.check(@account) == :ok
    end

    test "reports the status when the repository server will not answer" do
      stub(&Plug.Conn.send_resp(&1, 502, ""))

      assert Client.check(@account) == {:error, "The repository server returned HTTP 502"}
    end

    test "says so when no account has been resolved" do
      assert {:error, message} = Client.check(@connection)
      assert message =~ "Save the Tangled account"
    end
  end
end
