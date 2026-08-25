defmodule GitSync.Repo.Migrations.CreateConnections do
  use Ecto.Migration

  def change do
    create table(:connections) do
      add :kind, :string, null: false
      add :base_url, :string, null: false
      add :token, :binary
      add :ssh_key, :binary

      timestamps(type: :utc_datetime)
    end

    create unique_index(:connections, [:kind])
  end
end
