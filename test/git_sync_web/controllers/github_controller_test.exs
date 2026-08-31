defmodule GitSyncWeb.GithubControllerTest do
  use GitSyncWeb.ConnCase

  alias GitSync.Connections
  alias GitSync.Forge.Token

  setup :configure_forgejo

  setup %{conn: conn, connection: connection} do
    {:ok, _connection} = Connections.record_login(connection, "alice", Token.new("tok", nil, nil))
    Req.Test.stub(GitSync.Http, fn req_conn -> Req.Test.json(req_conn, []) end)

    %{conn: init_test_session(conn, %{"operator" => "alice"})}
  end

  defp enable_github(_context) do
    {:ok, connection} =
      Connections.enable_github(%{"client_id" => "cid", "client_secret" => "secret"})

    %{github: connection}
  end

  describe "before GitHub is enabled" do
    test "the connections page offers to enable it", %{conn: conn} do
      assert html_response(get(conn, ~p"/connections"), 200) =~ "github-form"
    end

    test "there is nothing to authorize", %{conn: conn} do
      conn = get(conn, ~p"/auth/github")

      assert redirected_to(conn) == ~p"/connections"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not enabled"
    end

    test "saving the OAuth app enables it", %{conn: conn} do
      conn =
        post(conn, ~p"/connections/github", %{
          "connection" => %{"client_id" => "cid", "client_secret" => "secret"}
        })

      assert redirected_to(conn) == ~p"/connections"
      assert Connections.github_enabled?()
    end

    test "an incomplete OAuth app is rejected", %{conn: conn} do
      conn =
        post(conn, ~p"/connections/github", %{
          "connection" => %{"client_id" => "cid", "client_secret" => ""}
        })

      assert html_response(conn, 200) =~ "can&#39;t be blank"
      refute Connections.github_enabled?()
    end
  end

  describe "authorizing" do
    setup :enable_github

    test "redirects to GitHub carrying a state parameter", %{conn: conn} do
      conn = get(conn, ~p"/auth/github")

      assert %URI{host: "github.com", query: query} = URI.parse(redirected_to(conn))
      assert %{"state" => state} = URI.decode_query(query)
      assert get_session(conn, "github_oauth_state") == state
    end

    test "stores the token the code buys", %{conn: conn} do
      Req.Test.stub(GitSync.Http, fn req_conn ->
        Req.Test.json(req_conn, %{"access_token" => "gho_tok"})
      end)

      conn =
        conn
        |> put_session("github_oauth_state", "st4te")
        |> get(~p"/auth/github/callback", %{"code" => "the-code", "state" => "st4te"})

      assert redirected_to(conn) == ~p"/connections"
      assert Connections.github().token == "gho_tok"
      refute get_session(conn, "github_oauth_state")
    end

    test "refuses a callback whose state does not match", %{conn: conn} do
      conn =
        conn
        |> put_session("github_oauth_state", "st4te")
        |> get(~p"/auth/github/callback", %{"code" => "the-code", "state" => "forged"})

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "did not match"
      refute Connections.github().token
    end

    test "reports a refused exchange", %{conn: conn} do
      Req.Test.stub(GitSync.Http, fn req_conn ->
        Req.Test.json(req_conn, %{"error_description" => "The code passed is incorrect."})
      end)

      conn =
        conn
        |> put_session("github_oauth_state", "st4te")
        |> get(~p"/auth/github/callback", %{"code" => "stale", "state" => "st4te"})

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "The code passed is incorrect."
      refute Connections.github().token
    end
  end

  describe "once connected" do
    setup :enable_github

    setup %{github: github} do
      {:ok, github} = Connections.store_token(github, Token.new("gho_tok", nil, nil))

      %{github: github}
    end

    test "the connections page reports how healthy GitHub is", %{conn: conn} do
      Req.Test.stub(GitSync.Http, fn req_conn ->
        Req.Test.json(req_conn, [
          %{
            "full_name" => "adam/git-sync",
            "clone_url" => "https://github.com/adam/git-sync.git",
            "private" => true
          }
        ])
      end)

      html = html_response(get(conn, ~p"/connections"), 200)

      assert html =~ "Healthy — 1 repository"
      refute html =~ "adam/git-sync"
    end

    test "disconnecting drops the token but keeps the OAuth app", %{conn: conn} do
      Req.Test.stub(GitSync.Http, fn req_conn -> Req.Test.json(req_conn, []) end)

      conn = delete(conn, ~p"/connections/github")

      assert redirected_to(conn) == ~p"/connections"
      refute Connections.github().token
      assert Connections.github_enabled?()
    end
  end
end
