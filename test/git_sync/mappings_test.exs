defmodule GitSync.MappingsTest do
  use GitSync.DataCase

  alias GitSync.Connection
  alias GitSync.Mappings

  setup do
    forgejo =
      Repo.insert!(%Connection{kind: :forgejo, base_url: "https://forge.test", token: "t"})

    github = Repo.insert!(%Connection{kind: :github, base_url: "https://github.com", token: "t"})
    tangled = Repo.insert!(%Connection{kind: :tangled, base_url: "https://knot.test"})

    %{forgejo: forgejo, github: github, tangled: tangled}
  end

  describe "create/1" do
    test "gives every mapping its own webhook secret", %{forgejo: forgejo, github: github} do
      {:ok, one} = Mappings.create(attrs(forgejo, github))
      {:ok, two} = Mappings.create(attrs(forgejo, github, destination_repo: "adam/other"))

      assert byte_size(one.webhook_secret) >= 32
      assert one.webhook_secret != two.webhook_secret
    end

    test "reports an invalid mapping", %{forgejo: forgejo, github: github} do
      assert {:error, %Ecto.Changeset{}} =
               Mappings.create(attrs(forgejo, github, source_repo: nil))
    end
  end

  describe "register_webhook/2" do
    test "records the hook the source forge created", %{forgejo: forgejo, github: github} do
      Req.Test.stub(GitSync.Http, fn conn ->
        assert conn.request_path == "/api/v1/repos/adam/git-sync/hooks"
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert %{"config" => %{"url" => "https://sync.test/webhooks/" <> _}} = JSON.decode!(body)

        conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{"id" => 42})
      end)

      {:ok, mapping} = Mappings.create(attrs(forgejo, github))

      assert {:ok, mapping} = Mappings.register_webhook(mapping, "https://sync.test")
      assert mapping.webhook_id == "42"
      assert Mappings.get(mapping.id).webhook_id == "42"
    end

    test "leaves a forge without webhooks on its timer", %{tangled: tangled, github: github} do
      {:ok, mapping} = Mappings.create(attrs(tangled, github))

      assert {:ok, mapping} = Mappings.register_webhook(mapping, "https://sync.test")
      assert is_nil(mapping.webhook_id)
    end

    test "reports a refused registration", %{forgejo: forgejo, github: github} do
      Req.Test.stub(GitSync.Http, fn conn -> Plug.Conn.send_resp(conn, 403, "") end)

      {:ok, mapping} = Mappings.create(attrs(forgejo, github))

      assert {:error, "Forgejo returned HTTP 403"} =
               Mappings.register_webhook(mapping, "https://sync.test")
    end
  end

  defp attrs(source, destination, overrides \\ []) do
    Enum.into(overrides, %{
      source_connection_id: source.id,
      source_repo: "adam/git-sync",
      destination_connection_id: destination.id,
      destination_repo: "adam/git-sync"
    })
  end
end
