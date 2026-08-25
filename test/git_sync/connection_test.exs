defmodule GitSync.ConnectionTest do
  use GitSync.DataCase

  alias GitSync.Connection

  @valid %{kind: :forgejo, base_url: "https://codeberg.org", token: "gho_secret"}

  test "requires kind and base_url" do
    changeset = Connection.changeset(%Connection{}, %{})

    assert %{kind: ["can't be blank"], base_url: ["can't be blank"]} = errors_on(changeset)
  end

  test "rejects a non-http base_url" do
    changeset = Connection.changeset(%Connection{}, %{@valid | base_url: "git@codeberg.org"})

    assert %{base_url: ["must be an http or https URL"]} = errors_on(changeset)
  end

  test "allows only one connection per kind" do
    assert {:ok, _} = Repo.insert(Connection.changeset(%Connection{}, @valid))

    assert {:error, changeset} = Repo.insert(Connection.changeset(%Connection{}, @valid))
    assert %{kind: ["has already been taken"]} = errors_on(changeset)
  end

  test "round-trips the token but stores it encrypted" do
    {:ok, connection} = Repo.insert(Connection.changeset(%Connection{}, @valid))

    assert Repo.get!(Connection, connection.id).token == "gho_secret"

    assert {:ok, %{rows: [[stored]]}} =
             Repo.query("SELECT token FROM connections WHERE id = ?", [connection.id])

    refute stored =~ "gho_secret"
  end

  test "redacts credentials from inspect output" do
    refute inspect(%Connection{token: "gho_secret", client_secret: "cs_secret"}) =~ "secret"
  end

  test "oauth_changeset requires the client credentials" do
    changeset =
      Connection.oauth_changeset(%Connection{}, %{
        kind: :forgejo,
        base_url: "https://codeberg.org"
      })

    assert %{client_id: ["can't be blank"], client_secret: ["can't be blank"]} =
             errors_on(changeset)
  end

  test "round-trips the client secret but stores it encrypted" do
    {:ok, connection} =
      Repo.insert(
        Connection.oauth_changeset(%Connection{}, %{
          kind: :forgejo,
          base_url: "https://codeberg.org",
          client_id: "abc",
          client_secret: "cs_secret"
        })
      )

    assert Repo.get!(Connection, connection.id).client_secret == "cs_secret"

    assert {:ok, %{rows: [[stored]]}} =
             Repo.query("SELECT client_secret FROM connections WHERE id = ?", [connection.id])

    refute stored =~ "cs_secret"
  end
end
