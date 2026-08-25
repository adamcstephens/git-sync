defmodule GitSyncWeb.WebhookControllerTest do
  use GitSyncWeb.ConnCase

  alias GitSync.Connection
  alias GitSync.Mappings
  alias GitSync.Repo
  alias GitSync.Sync

  @body ~s({"ref":"refs/heads/main"})

  setup %{conn: conn} do
    source = Repo.insert!(%Connection{kind: :forgejo, base_url: "https://forge.test", token: "t"})

    destination =
      Repo.insert!(%Connection{kind: :github, base_url: "https://github.com", token: "t"})

    {:ok, mapping} =
      Mappings.create(%{
        source_connection_id: source.id,
        source_repo: "adam/git-sync",
        destination_connection_id: destination.id,
        destination_repo: "adam/git-sync"
      })

    conn = put_req_header(conn, "content-type", "application/json")

    %{conn: conn, mapping: mapping}
  end

  test "wakes the runner for a signed delivery", %{conn: conn, mapping: mapping} do
    test = self()
    mapping_id = mapping.id

    {:ok, pid} =
      Sync.start_runner(mapping,
        sync_fun: fn m -> send(test, {:synced, m.id}) end,
        debounce_ms: 0
      )

    on_exit(fn -> Sync.stop_runner(mapping_id) end)
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
    assert_receive {:synced, _}

    conn =
      conn
      |> put_req_header("x-forgejo-signature", signature(@body, mapping.webhook_secret))
      |> post(~p"/webhooks/#{mapping.id}", @body)

    assert response(conn, 204)
    assert_receive {:synced, ^mapping_id}
  end

  test "refuses a delivery signed with the wrong secret", %{conn: conn, mapping: mapping} do
    conn =
      conn
      |> put_req_header("x-forgejo-signature", signature(@body, "wrong"))
      |> post(~p"/webhooks/#{mapping.id}", @body)

    assert response(conn, 401)
  end

  test "refuses an unsigned delivery", %{conn: conn, mapping: mapping} do
    conn = post(conn, ~p"/webhooks/#{mapping.id}", @body)

    assert response(conn, 401)
  end

  test "does not reveal whether an unknown mapping exists", %{conn: conn} do
    conn = post(conn, ~p"/webhooks/999", @body)

    assert response(conn, 404)
  end

  test "needs no operator session", %{conn: conn, mapping: mapping} do
    conn =
      conn
      |> put_req_header("x-forgejo-signature", signature(@body, mapping.webhook_secret))
      |> post(~p"/webhooks/#{mapping.id}", @body)

    assert response(conn, 204)
  end

  defp signature(body, secret),
    do: Base.encode16(:crypto.mac(:hmac, :sha256, secret, body), case: :lower)
end
