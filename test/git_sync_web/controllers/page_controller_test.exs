defmodule GitSyncWeb.PageControllerTest do
  use GitSyncWeb.ConnCase

  alias GitSync.Connection
  alias GitSync.Destination
  alias GitSync.Repo
  alias GitSync.Run
  alias GitSync.Source

  setup :configure_forgejo

  setup %{conn: conn, connection: connection} do
    {:ok, conn: init_test_session(conn, %{"operator" => "alice"}), connection: connection}
  end

  test "GET / shows empty states and management links", %{conn: conn} do
    html = html_response(get(conn, ~p"/"), 200)

    assert html =~ "No sources configured"
    assert html =~ "No runs yet"
    assert html =~ ~s(href="/sources")
    assert html =~ ~s(href="/connections")
  end

  test "GET / shows configuration counts and the latest run for each source", %{
    conn: conn,
    connection: connection
  } do
    other =
      Repo.insert!(%Connection{kind: :github, base_url: "https://github.com", token: "token"})

    first = source(connection, "alice/first")
    second = source(other, "alice/second", false)
    unused = source(connection, "alice/unused")
    destination(first, other, "alice/mirror")
    destination(first, other, "alice/paused", false)
    destination(second, connection, "alice/backup")
    run(first, :failure, ~U[2025-01-01 00:00:00Z])
    run(first, :success, ~U[2025-01-02 00:00:00Z])
    run(second, :running, ~U[2025-01-03 00:00:00Z])

    html = html_response(get(conn, ~p"/"), 200)

    assert html =~ "3 sources"
    assert html =~ "2 enabled, 1 disabled"
    assert html =~ "3 destinations"
    assert html =~ "2 enabled, 1 disabled"
    assert html =~ "alice/first"
    assert html =~ "alice/second"
    assert html =~ "alice/unused"
    assert html =~ "https://github.com"
    assert html =~ ~s(href="/sources/#{unused.id}")

    first_row =
      html
      |> String.split(~s(id="source-#{first.id}"), parts: 2)
      |> List.last()
      |> String.split("</article>", parts: 2)
      |> hd()

    second_row =
      html
      |> String.split(~s(id="source-#{second.id}"), parts: 2)
      |> List.last()
      |> String.split("</article>", parts: 2)
      |> hd()

    unused_row =
      html
      |> String.split(~s(id="source-#{unused.id}"), parts: 2)
      |> List.last()
      |> String.split("</article>", parts: 2)
      |> hd()

    assert first_row =~ "Success"
    refute first_row =~ "Failure"
    assert second_row =~ "Running"
    assert second_row =~ "Disabled"
    assert unused_row =~ "Never run"
    assert html =~ "Failure"
    assert html =~ "2025-01-03"
  end

  test "GET / limits recent runs to ten across sources with stable tie ordering", %{
    conn: conn,
    connection: connection
  } do
    first = source(connection, "alice/first")
    second = source(connection, "alice/second")

    runs =
      for index <- 1..11 do
        source = if rem(index, 2) == 0, do: second, else: first
        run(source, :success, ~U[2025-01-01 00:00:00Z])
      end

    html = html_response(get(conn, ~p"/"), 200)
    recent = html |> String.split(~s(id="recent-runs"), parts: 2) |> List.last()
    ids = Regex.scan(~r/id="recent-run-(\d+)"/, recent, capture: :all_but_first)

    assert Enum.map(ids, fn [id] -> String.to_integer(id) end) ==
             runs |> Enum.reverse() |> Enum.take(10) |> Enum.map(& &1.id)
  end

  test "GET / redirects anonymous visitors to the login page", %{conn: conn} do
    conn = conn |> delete_session(:operator) |> get(~p"/")
    assert redirected_to(conn) == ~p"/login"
  end

  defp source(connection, repo, enabled \\ true) do
    Repo.insert!(%Source{connection_id: connection.id, repo: repo, enabled: enabled})
  end

  defp destination(source, connection, repo, enabled \\ true) do
    Repo.insert!(%Destination{
      source_id: source.id,
      connection_id: connection.id,
      repo: repo,
      enabled: enabled
    })
  end

  defp run(source, status, started_at, log \\ nil) do
    Repo.insert!(%Run{source_id: source.id, status: status, started_at: started_at, log: log})
  end
end
