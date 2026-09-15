defmodule GitSync.SourcesTest do
  use GitSync.DataCase

  alias GitSync.Connection
  alias GitSync.Sources

  setup do
    forgejo =
      Repo.insert!(%Connection{kind: :forgejo, base_url: "https://forge.test", token: "t"})

    github = Repo.insert!(%Connection{kind: :github, base_url: "https://github.com", token: "t"})
    tangled = Repo.insert!(%Connection{kind: :tangled, base_url: "https://knot.test"})

    %{forgejo: forgejo, github: github, tangled: tangled}
  end

  describe "create/1" do
    test "gives every source its own webhook secret", %{forgejo: forgejo} do
      {:ok, one} = Sources.create(attrs(forgejo))
      {:ok, two} = Sources.create(attrs(forgejo, repo: "adam/other"))

      assert byte_size(one.webhook_secret) >= 32
      assert one.webhook_secret != two.webhook_secret
    end

    test "reports an invalid source", %{forgejo: forgejo} do
      assert {:error, %Ecto.Changeset{}} = Sources.create(attrs(forgejo, repo: nil))
    end
  end

  describe "create_with_destination/2" do
    test "creates both", %{forgejo: forgejo, github: github} do
      assert {:ok, source} =
               Sources.create_with_destination(attrs(forgejo), destination_attrs(github))

      assert [destination] = Sources.get(source.id).destinations
      assert destination.repo == "adam/mirror"
    end

    test "keeps no source when its destination is invalid", %{forgejo: forgejo, github: github} do
      assert {:error, changeset} =
               Sources.create_with_destination(
                 attrs(forgejo),
                 destination_attrs(github, repo: "mirror")
               )

      assert %GitSync.Destination{} = changeset.data
      assert Sources.list() == []
    end

    test "reports an invalid source", %{forgejo: forgejo, github: github} do
      assert {:error, changeset} =
               Sources.create_with_destination(
                 attrs(forgejo, repo: ""),
                 destination_attrs(github)
               )

      assert %GitSync.Source{} = changeset.data
    end
  end

  describe "list/0" do
    test "returns the sources with their forges and destinations", %{
      forgejo: forgejo,
      github: github
    } do
      {:ok, source} = Sources.create_with_destination(attrs(forgejo), destination_attrs(github))

      assert [listed] = Sources.list()
      assert listed.id == source.id
      assert listed.connection.base_url == "https://forge.test"
      assert [destination] = listed.destinations
      assert destination.connection.base_url == "https://github.com"
    end
  end

  describe "update/2" do
    test "switches a source off", %{forgejo: forgejo} do
      {:ok, source} = Sources.create(attrs(forgejo))

      assert {:ok, source} = Sources.update(source, %{enabled: false})
      refute source.enabled
    end

    test "reports an invalid change", %{forgejo: forgejo} do
      {:ok, source} = Sources.create(attrs(forgejo))

      assert {:error, %Ecto.Changeset{}} = Sources.update(source, %{interval_seconds: 1})
    end
  end

  describe "delete/1" do
    test "removes the source", %{forgejo: forgejo} do
      {:ok, source} = Sources.create(attrs(forgejo))

      assert {:ok, _source} = Sources.delete(source)
      assert is_nil(Sources.get(source.id))
    end
  end

  describe "register_webhook/2" do
    test "records the hook the forge created", %{forgejo: forgejo} do
      Req.Test.stub(GitSync.Http, fn conn ->
        assert conn.request_path == "/api/v1/repos/adam/git-sync/hooks"
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert %{"config" => %{"url" => "https://sync.test/webhooks/" <> _}} = JSON.decode!(body)

        conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{"id" => 42})
      end)

      {:ok, source} = Sources.create(attrs(forgejo))

      assert {:ok, source} = Sources.register_webhook(source, "https://sync.test")
      assert source.webhook_id == "42"
      assert Sources.get(source.id).webhook_id == "42"
    end

    test "leaves a forge without webhooks on its timer", %{tangled: tangled} do
      {:ok, source} = Sources.create(attrs(tangled))

      assert {:ok, source} = Sources.register_webhook(source, "https://sync.test")
      assert is_nil(source.webhook_id)
    end

    test "reports a refused registration", %{forgejo: forgejo} do
      Req.Test.stub(GitSync.Http, fn conn -> Plug.Conn.send_resp(conn, 403, "") end)

      {:ok, source} = Sources.create(attrs(forgejo))

      assert {:error, "Forgejo returned HTTP 403"} =
               Sources.register_webhook(source, "https://sync.test")
    end
  end

  describe "reconcile_webhooks/0" do
    test "reconciles stored Forgejo hooks without replacing them", %{
      forgejo: forgejo,
      github: github
    } do
      {:ok, forgejo_source} = Sources.create(attrs(forgejo))
      {:ok, github_source} = Sources.create(attrs(github, repo: "adam/github"))

      forgejo_source =
        forgejo_source
        |> Ecto.Changeset.change(webhook_id: "42")
        |> Repo.update!()

      github_source
      |> Ecto.Changeset.change(webhook_id: "99")
      |> Repo.update!()

      Req.Test.stub(GitSync.Http, fn conn ->
        assert conn.request_path == "/api/v1/repos/adam/git-sync/hooks/42"

        case conn.method do
          "GET" ->
            Req.Test.json(conn, %{"events" => ["push"]})

          "PATCH" ->
            Req.Test.json(conn, %{"id" => 42})
        end
      end)

      assert :ok = Sources.reconcile_webhooks()
      assert Sources.get(forgejo_source.id).webhook_id == "42"
    end
  end

  defp attrs(connection, overrides \\ []),
    do: Enum.into(overrides, %{connection_id: connection.id, repo: "adam/git-sync"})

  defp destination_attrs(connection, overrides \\ []),
    do: Enum.into(overrides, %{connection_id: connection.id, repo: "adam/mirror"})
end
