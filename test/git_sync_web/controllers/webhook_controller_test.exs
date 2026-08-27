defmodule GitSyncWeb.WebhookControllerTest do
  use GitSyncWeb.ConnCase

  alias GitSync.Connection
  alias GitSync.Sources
  alias GitSync.Repo
  alias GitSync.Sync

  @body ~s({"ref":"refs/heads/main"})

  setup %{conn: conn} do
    forge = Repo.insert!(%Connection{kind: :forgejo, base_url: "https://forge.test", token: "t"})
    github = Repo.insert!(%Connection{kind: :github, base_url: "https://github.com", token: "t"})

    {:ok, source} =
      Sources.create_with_destination(
        %{connection_id: forge.id, repo: "adam/git-sync"},
        %{connection_id: github.id, repo: "adam/mirror"}
      )

    conn = put_req_header(conn, "content-type", "application/json")

    %{conn: conn, source: source}
  end

  test "wakes the runner for a signed delivery", %{conn: conn, source: source} do
    test = self()
    source_id = source.id

    {:ok, pid} =
      Sync.start_runner(source,
        sync_fun: fn m -> send(test, {:synced, m.id}) end,
        debounce_ms: 0
      )

    on_exit(fn -> Sync.stop_runner(source_id) end)
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
    assert_receive {:synced, _}

    conn =
      conn
      |> put_req_header("x-forgejo-signature", signature(@body, source.webhook_secret))
      |> post(~p"/webhooks/#{source.id}", @body)

    assert response(conn, 204)
    assert_receive {:synced, ^source_id}
  end

  test "refuses a delivery signed with the wrong secret", %{conn: conn, source: source} do
    conn =
      conn
      |> put_req_header("x-forgejo-signature", signature(@body, "wrong"))
      |> post(~p"/webhooks/#{source.id}", @body)

    assert response(conn, 401)
  end

  test "refuses an unsigned delivery", %{conn: conn, source: source} do
    conn = post(conn, ~p"/webhooks/#{source.id}", @body)

    assert response(conn, 401)
  end

  test "does not reveal whether an unknown source exists", %{conn: conn} do
    conn = post(conn, ~p"/webhooks/999", @body)

    assert response(conn, 404)
  end

  test "needs no operator session", %{conn: conn, source: source} do
    conn =
      conn
      |> put_req_header("x-forgejo-signature", signature(@body, source.webhook_secret))
      |> post(~p"/webhooks/#{source.id}", @body)

    assert response(conn, 204)
  end

  defp signature(body, secret),
    do: Base.encode16(:crypto.mac(:hmac, :sha256, secret, body), case: :lower)
end
