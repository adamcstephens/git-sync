defmodule GitSyncWeb.DestinationControllerTest do
  use GitSyncWeb.ConnCase

  alias GitSync.Connection
  alias GitSync.Destinations
  alias GitSync.Forge.Token
  alias GitSync.Repo
  alias GitSync.Sources

  setup :configure_forgejo

  setup %{conn: conn, connection: connection} do
    {:ok, forgejo} =
      GitSync.Connections.record_login(connection, "alice", Token.new("tok", nil, nil))

    github = Repo.insert!(%Connection{kind: :github, base_url: "https://github.com", token: "t"})

    {:ok, source} =
      Sources.create_with_destination(
        %{"connection_id" => forgejo.id, "repo" => "adam/git-sync"},
        %{"connection_id" => github.id, "repo" => "adam/mirror"}
      )

    %{
      conn: init_test_session(conn, %{"operator" => "alice"}),
      github: github,
      source: Sources.get(source.id)
    }
  end

  describe "create" do
    test "adds another destination to the source", %{conn: conn} = context do
      %{source: source, github: github} = context

      conn =
        post(conn, ~p"/sources/#{source}/destinations",
          destination: %{connection_id: github.id, repo: "adam/second-mirror"}
        )

      assert redirected_to(conn) == ~p"/sources/#{source}"

      assert Enum.map(Sources.get(source.id).destinations, & &1.repo) == [
               "adam/mirror",
               "adam/second-mirror"
             ]
    end

    test "reports an invalid destination", %{conn: conn} = context do
      %{source: source, github: github} = context

      conn =
        post(conn, ~p"/sources/#{source}/destinations",
          destination: %{connection_id: github.id, repo: "mirror"}
        )

      assert redirected_to(conn) == ~p"/sources/#{source}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "must look like owner/name"
      assert length(Sources.get(source.id).destinations) == 1
    end
  end

  describe "update" do
    test "switches a destination off, leaving the source running", %{conn: conn} = context do
      %{source: source} = context
      destination = hd(source.destinations)

      conn =
        put(conn, ~p"/sources/#{source}/destinations/#{destination}",
          destination: %{enabled: "false"}
        )

      assert redirected_to(conn) == ~p"/sources/#{source}"
      refute Destinations.get(destination.id).enabled
      assert Sources.get(source.id).enabled
    end
  end

  describe "delete" do
    test "removes the destination and keeps the source", %{conn: conn} = context do
      %{source: source} = context
      destination = hd(source.destinations)

      conn = delete(conn, ~p"/sources/#{source}/destinations/#{destination}")

      assert redirected_to(conn) == ~p"/sources/#{source}"
      assert is_nil(Destinations.get(destination.id))
      assert Sources.get(source.id).destinations == []
    end
  end
end
