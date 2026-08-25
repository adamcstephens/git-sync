defmodule GitSync.Repo.Migrations.CreateMappings do
  use Ecto.Migration

  def change do
    create table(:mappings) do
      add :source_connection_id, references(:connections, on_delete: :restrict), null: false
      add :source_repo, :string, null: false
      add :destination_connection_id, references(:connections, on_delete: :restrict), null: false
      add :destination_repo, :string, null: false
      add :interval_seconds, :integer, null: false, default: 3600
      add :enabled, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:mappings, [:source_connection_id])
    create unique_index(:mappings, [:destination_connection_id, :destination_repo])
  end
end
