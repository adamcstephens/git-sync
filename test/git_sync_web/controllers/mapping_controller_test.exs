defmodule GitSyncWeb.MappingControllerTest do
  use GitSyncWeb.ConnCase

  alias GitSync.Connection
  alias GitSync.Forge.Token
  alias GitSync.Mapping
  alias GitSync.Mappings
  alias GitSync.Repo
  alias GitSync.Run
  alias GitSync.Sync
  alias GitSyncWeb.MappingController
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
    test "lists the mappings", %{conn: conn} = context do
      mapping(context)

      html = html_response(get(conn, ~p"/mappings"), 200)

      assert html =~ "adam/git-sync"
      assert html =~ "adam/mirror"
    end

    test "offers the connections as sources and destinations", %{conn: conn} do
      html = html_response(get(conn, ~p"/mappings"), 200)

      assert html =~ "https://forge.test"
      assert html =~ "https://github.com"
    end

    test "asks for a forge before a repository, with nothing to autofill", %{conn: conn} do
      html = html_response(get(conn, ~p"/mappings"), 200)

      assert html =~ "data-on:change="
      assert html =~ "/mappings/repos"
      assert html =~ ~s(<select id="mapping_source_repo" name="mapping[source_repo]")
      assert html =~ "Choose a forge first"
      refute html =~ ~s(type="text" name="mapping[source_repo]")
    end
  end

  describe "repos" do
    test "offers the repositories of the chosen forge", %{conn: conn, forgejo: forgejo} do
      Req.Test.stub(GitSync.Http, fn req_conn ->
        Req.Test.json(req_conn, [
          %{
            "full_name" => "adam/git-sync",
            "clone_url" => "https://forge.test/adam/git-sync.git",
            "private" => false
          }
        ])
      end)

      conn = get(conn, ~p"/mappings/repos?datastar=#{signals(forgejo)}")

      assert response(conn, 200) =~ "event: datastar-patch-elements"
      assert response(conn, 200) =~ ~s(id="source-repo-field")
      assert response(conn, 200) =~ ~s(<option value="adam/git-sync")
    end

    test "lets the repositories be searched by typing", %{conn: conn, forgejo: forgejo} do
      Req.Test.stub(GitSync.Http, fn req_conn ->
        Req.Test.json(req_conn, [
          %{
            "full_name" => "adam/git-sync",
            "clone_url" => "https://forge.test/adam/git-sync.git",
            "private" => false
          }
        ])
      end)

      body = response(get(conn, ~p"/mappings/repos?datastar=#{signals(forgejo)}"), 200)

      assert body =~ ~s(<input type="text" name="mapping[source_repo]")
      assert body =~ ~s(list="mapping_source_repo-options")
      assert body =~ ~s(<datalist id="mapping_source_repo-options">)
      refute body =~ ~s(<select id="mapping_source_repo")
    end

    test "falls back to a typed name when the forge cannot be listed", %{
      conn: conn,
      forgejo: forgejo
    } do
      Req.Test.stub(GitSync.Http, &Plug.Conn.send_resp(&1, 401, ""))

      body = response(get(conn, ~p"/mappings/repos?datastar=#{signals(forgejo)}"), 200)

      assert body =~ ~s(type="text" name="mapping[source_repo]")
      assert body =~ ~s(autocomplete="off")
      assert body =~ "Could not list repositories"
    end

    test "asks for a forge before a repository", %{conn: conn} do
      body = response(get(conn, ~p"/mappings/repos?datastar=#{JSON.encode!(%{})}"), 200)

      assert body =~ "Choose a forge first"
      refute body =~ "Could not list repositories"
    end
  end

  describe "create" do
    test "adds a mapping and registers its webhook", %{conn: conn} = context do
      Req.Test.stub(GitSync.Http, fn req_conn ->
        req_conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{"id" => 42})
      end)

      conn = post(conn, ~p"/mappings", mapping: attrs(context))

      assert %Mapping{} = mapping = List.first(Mappings.list())
      assert redirected_to(conn) == ~p"/mappings/#{mapping}"
      assert mapping.source_repo == "adam/git-sync"
      assert mapping.webhook_id == "42"
    end

    test "reports an invalid mapping", %{conn: conn} = context do
      Req.Test.stub(GitSync.Http, &Req.Test.json(&1, []))

      conn = post(conn, ~p"/mappings", mapping: %{attrs(context) | source_repo: ""})

      assert html_response(conn, 200) =~ "can&#39;t be blank"
      assert Mappings.list() == []
    end

    test "keeps the mapping when the forge refuses the webhook", %{conn: conn} = context do
      Req.Test.stub(GitSync.Http, &Plug.Conn.send_resp(&1, 403, ""))

      conn = post(conn, ~p"/mappings", mapping: attrs(context))

      assert %Mapping{} = mapping = List.first(Mappings.list())
      assert redirected_to(conn) == ~p"/mappings/#{mapping}"
      assert is_nil(mapping.webhook_id)
    end
  end

  describe "show" do
    test "lists the runs of the mapping", %{conn: conn} = context do
      mapping = mapping(context)
      run(mapping, status: :success, log: "$ git push")

      html = html_response(get(conn, ~p"/mappings/#{mapping}"), 200)

      assert html =~ "success"
      assert html =~ "$ git push"
    end

    test "subscribes the page to run updates", %{conn: conn} = context do
      mapping = mapping(context)

      html = html_response(get(conn, ~p"/mappings/#{mapping}"), 200)

      assert html =~ "data-init="
      assert html =~ "/mappings/#{mapping.id}/events"
    end
  end

  describe "handle_run/2" do
    test "patches the run list into subscribed pages", context do
      mapping = mapping(context)
      run = run(mapping, status: :success, log: "$ git push")

      conn = SSE.open(build_conn())
      assert {:cont, conn} = MappingController.handle_run({:run, run}, conn)

      assert conn.resp_body =~ "event: datastar-patch-elements"
      assert conn.resp_body =~ ~s(data: elements <section id="runs">)
      assert conn.resp_body =~ "$ git push"
    end
  end

  describe "update" do
    test "switches a mapping off and stops its runner", %{conn: conn} = context do
      mapping = mapping(context)
      {:ok, pid} = Sync.start_runner(mapping, sync_fun: fn _mapping -> {:ok, :run} end)
      ref = Process.monitor(pid)

      conn = put(conn, ~p"/mappings/#{mapping}", mapping: %{enabled: "false"})

      assert redirected_to(conn) == ~p"/mappings/#{mapping}"
      refute Mappings.get(mapping.id).enabled
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    end
  end

  describe "sync" do
    test "pulls the next sync forward", %{conn: conn} = context do
      mapping = mapping(context)
      conn = post(conn, ~p"/mappings/#{mapping}/sync")

      assert redirected_to(conn) == ~p"/mappings/#{mapping}"
    end
  end

  describe "delete" do
    test "removes the mapping and its runner", %{conn: conn} = context do
      mapping = mapping(context)
      {:ok, pid} = Sync.start_runner(mapping, sync_fun: fn _mapping -> {:ok, :run} end)
      ref = Process.monitor(pid)

      conn = delete(conn, ~p"/mappings/#{mapping}")

      assert redirected_to(conn) == ~p"/mappings"
      assert is_nil(Mappings.get(mapping.id))
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    end
  end

  defp signals(connection) do
    JSON.encode!(%{
      "source_connection_id" => to_string(connection.id),
      "destination_connection_id" => ""
    })
  end

  defp attrs(%{forgejo: forgejo, github: github}) do
    %{
      source_connection_id: forgejo.id,
      source_repo: "adam/git-sync",
      destination_connection_id: github.id,
      destination_repo: "adam/mirror",
      interval_seconds: "900"
    }
  end

  defp mapping(context) do
    {:ok, mapping} = Mappings.create(attrs(context))
    mapping
  end

  defp run(%Mapping{} = mapping, attrs) do
    %Run{}
    |> Run.changeset(
      Enum.into(attrs, %{
        mapping_id: mapping.id,
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now()
      })
    )
    |> Repo.insert!()
  end
end
