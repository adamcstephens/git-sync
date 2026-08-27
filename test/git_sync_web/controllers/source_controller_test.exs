defmodule GitSyncWeb.SourceControllerTest do
  use GitSyncWeb.ConnCase

  alias GitSync.Connection
  alias GitSync.Destination
  alias GitSync.Forge.Token
  alias GitSync.Repo
  alias GitSync.Run
  alias GitSync.RunTarget
  alias GitSync.Source
  alias GitSync.Sources
  alias GitSync.Sync
  alias GitSyncWeb.SourceController
  alias GitSyncWeb.SSE

  setup :configure_forgejo

  setup %{conn: conn, connection: connection} do
    {:ok, forgejo} =
      GitSync.Connections.record_login(connection, "alice", Token.new("tok", nil, nil))

    github = Repo.insert!(%Connection{kind: :github, base_url: "https://github.com", token: "t"})

    root = Path.join(System.tmp_dir!(), "git-sync-#{System.unique_integer([:positive])}")
    Application.put_env(:git_sync, :workspace_root, root)

    on_exit(fn ->
      Enum.each(Sync.running(), &Sync.stop_runner/1)
      File.rm_rf!(root)
    end)

    %{
      conn: init_test_session(conn, %{"operator" => "alice"}),
      forgejo: forgejo,
      github: github
    }
  end

  describe "index" do
    test "lists each source with its destinations", %{conn: conn} = context do
      source = source(context)
      destination(source, context, repo: "adam/second-mirror")

      html = html_response(get(conn, ~p"/sources"), 200)

      assert html =~ "adam/git-sync"
      assert html =~ "adam/mirror"
      assert html =~ "adam/second-mirror"
    end

    test "names the source once however many destinations it has", %{conn: conn} = context do
      source = source(context)
      destination(source, context, repo: "adam/second-mirror")

      html = html_response(get(conn, ~p"/sources"), 200)

      assert length(String.split(html, "adam/git-sync")) - 1 == 1
    end

    test "offers the connections as sources and destinations", %{conn: conn} do
      html = html_response(get(conn, ~p"/sources"), 200)

      assert html =~ "https://forge.test"
      assert html =~ "https://github.com"
    end

    test "asks for a forge before a repository, with nothing to autofill", %{conn: conn} do
      html = html_response(get(conn, ~p"/sources"), 200)

      assert html =~ "data-on:change="
      assert html =~ "/sources/repos"
      assert html =~ ~s(<select id="source_repo" name="source[repo]")
      assert html =~ ~s(<select id="destination_repo" name="destination[repo]")
      assert html =~ "Choose a forge first"
    end
  end

  describe "repos" do
    test "offers the repositories of the chosen forge", %{conn: conn, forgejo: forgejo} do
      stub_repos()

      conn = get(conn, ~p"/sources/repos?datastar=#{signals(forgejo)}")

      assert response(conn, 200) =~ "event: datastar-patch-elements"
      assert response(conn, 200) =~ ~s(id="source-repo-field")
      assert response(conn, 200) =~ ~s(<option value="adam/git-sync")
    end

    test "lets the repositories be searched by typing", %{conn: conn, forgejo: forgejo} do
      stub_repos()

      body = response(get(conn, ~p"/sources/repos?datastar=#{signals(forgejo)}"), 200)

      assert body =~ ~s(<input type="text" name="source[repo]")
      assert body =~ ~s(list="source_repo-options")
      assert body =~ ~s(<datalist id="source_repo-options">)
      refute body =~ ~s(<select id="source_repo")
    end

    test "repaints only the pickers the page is showing", %{conn: conn, github: github} do
      stub_repos()

      signals = JSON.encode!(%{"destination_connection_id" => to_string(github.id)})
      body = response(get(conn, ~p"/sources/repos?datastar=#{signals}"), 200)

      assert body =~ ~s(id="destination-repo-field")
      refute body =~ ~s(id="source-repo-field")
    end

    test "falls back to a typed name when the forge cannot be listed", %{
      conn: conn,
      forgejo: forgejo
    } do
      Req.Test.stub(GitSync.Http, &Plug.Conn.send_resp(&1, 401, ""))

      body = response(get(conn, ~p"/sources/repos?datastar=#{signals(forgejo)}"), 200)

      assert body =~ ~s(type="text" name="source[repo]")
      assert body =~ ~s(autocomplete="off")
      assert body =~ "Could not list repositories"
    end

    test "asks for a forge before a repository", %{conn: conn} do
      signals = JSON.encode!(%{"source_connection_id" => ""})
      body = response(get(conn, ~p"/sources/repos?datastar=#{signals}"), 200)

      assert body =~ "Choose a forge first"
      refute body =~ "Could not list repositories"
    end
  end

  describe "create" do
    test "adds a source with its first destination and registers one webhook",
         %{conn: conn} = context do
      hooks = stub_hooks()

      conn = post(conn, ~p"/sources", attrs(context))

      assert %Source{} = source = List.first(Sources.list())
      assert redirected_to(conn) == ~p"/sources/#{source}"
      assert source.repo == "adam/git-sync"
      assert source.webhook_id == "42"
      assert [%Destination{repo: "adam/mirror"}] = source.destinations
      assert Agent.get(hooks, & &1) == 1
    end

    test "reports an invalid source", %{conn: conn} = context do
      Req.Test.stub(GitSync.Http, &Req.Test.json(&1, []))

      params = put_in(attrs(context), ["source", "repo"], "")
      conn = post(conn, ~p"/sources", params)

      assert html_response(conn, 200) =~ "can&#39;t be blank"
      assert Sources.list() == []
    end

    test "keeps no source when its destination is invalid", %{conn: conn} = context do
      Req.Test.stub(GitSync.Http, &Req.Test.json(&1, []))

      params = put_in(attrs(context), ["destination", "repo"], "mirror")
      conn = post(conn, ~p"/sources", params)

      assert html_response(conn, 200) =~ "must look like owner/name"
      assert Sources.list() == []
    end

    test "keeps the source when the forge refuses the webhook", %{conn: conn} = context do
      Req.Test.stub(GitSync.Http, &Plug.Conn.send_resp(&1, 403, ""))

      conn = post(conn, ~p"/sources", attrs(context))

      assert %Source{} = source = List.first(Sources.list())
      assert redirected_to(conn) == ~p"/sources/#{source}"
      assert is_nil(source.webhook_id)
    end
  end

  describe "show" do
    test "lists the destinations and the runs", %{conn: conn} = context do
      source = source(context)
      run(source, context, log: "$ git clone", target_log: "$ git push")

      html = html_response(get(conn, ~p"/sources/#{source}"), 200)

      assert html =~ "adam/mirror"
      assert html =~ "success"
      assert html =~ "$ git clone"
      assert html =~ "$ git push"
    end

    test "offers to add another destination without re-asking for the source",
         %{conn: conn} = context do
      source = source(context)

      html = html_response(get(conn, ~p"/sources/#{source}"), 200)

      assert html =~ ~s(action="/sources/#{source.id}/destinations")
      assert html =~ ~s(name="destination[repo]")
      refute html =~ ~s(name="source[repo]")
    end

    test "subscribes the page to run updates", %{conn: conn} = context do
      source = source(context)

      html = html_response(get(conn, ~p"/sources/#{source}"), 200)

      assert html =~ "data-init="
      assert html =~ "/sources/#{source.id}/events"
    end
  end

  describe "handle_run/2" do
    test "patches the run list into subscribed pages", context do
      source = source(context)
      run = run(source, context, log: "$ git clone", target_log: "$ git push")

      conn = SSE.open(build_conn())
      assert {:cont, conn} = SourceController.handle_run({:run, run}, conn)

      assert conn.resp_body =~ "event: datastar-patch-elements"
      assert conn.resp_body =~ ~s(data: elements <section id="runs">)
      assert conn.resp_body =~ "$ git push"
    end
  end

  describe "update" do
    test "switches a source off and stops its runner", %{conn: conn} = context do
      source = source(context)
      {:ok, pid} = Sync.start_runner(source, sync_fun: fn _source -> {:ok, :run} end)
      ref = Process.monitor(pid)

      conn = put(conn, ~p"/sources/#{source}", source: %{enabled: "false"})

      assert redirected_to(conn) == ~p"/sources/#{source}"
      refute Sources.get(source.id).enabled
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    end
  end

  describe "sync" do
    test "pulls the next sync forward", %{conn: conn} = context do
      source = source(context)
      conn = post(conn, ~p"/sources/#{source}/sync")

      assert redirected_to(conn) == ~p"/sources/#{source}"
    end
  end

  describe "delete" do
    test "removes the source, its destinations and its runner", %{conn: conn} = context do
      source = source(context)
      {:ok, pid} = Sync.start_runner(source, sync_fun: fn _source -> {:ok, :run} end)
      ref = Process.monitor(pid)

      conn = delete(conn, ~p"/sources/#{source}")

      assert redirected_to(conn) == ~p"/sources"
      assert is_nil(Sources.get(source.id))
      assert Repo.aggregate(Destination, :count) == 0
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    end
  end

  defp stub_repos do
    Req.Test.stub(GitSync.Http, fn conn ->
      Req.Test.json(conn, [
        %{
          "full_name" => "adam/git-sync",
          "clone_url" => "https://forge.test/adam/git-sync.git",
          "private" => false
        }
      ])
    end)
  end

  defp stub_hooks do
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    Req.Test.stub(GitSync.Http, fn conn ->
      Agent.update(calls, &(&1 + 1))
      conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{"id" => 42})
    end)

    calls
  end

  defp signals(connection) do
    JSON.encode!(%{
      "source_connection_id" => to_string(connection.id),
      "destination_connection_id" => ""
    })
  end

  defp attrs(%{forgejo: forgejo, github: github}) do
    %{
      "source" => %{
        "connection_id" => forgejo.id,
        "repo" => "adam/git-sync",
        "interval_seconds" => "900"
      },
      "destination" => %{"connection_id" => github.id, "repo" => "adam/mirror"}
    }
  end

  defp source(context) do
    params = attrs(context)
    {:ok, source} = Sources.create_with_destination(params["source"], params["destination"])
    Sources.get(source.id)
  end

  defp destination(source, %{github: github}, overrides) do
    Repo.insert!(%Destination{
      source_id: source.id,
      connection_id: github.id,
      repo: Keyword.fetch!(overrides, :repo)
    })
  end

  defp run(%Source{} = source, _context, attrs) do
    run =
      Repo.insert!(%Run{
        source_id: source.id,
        status: :success,
        started_at: DateTime.utc_now(:second),
        finished_at: DateTime.utc_now(:second),
        log: Keyword.fetch!(attrs, :log)
      })

    Repo.insert!(%RunTarget{
      run_id: run.id,
      destination_id: hd(source.destinations).id,
      status: :success,
      log: Keyword.fetch!(attrs, :target_log)
    })

    GitSync.Runs.get(run.id)
  end
end
