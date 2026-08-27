defmodule GitSync.Repo.Migrations.CreateSourcesAndDestinations do
  use Ecto.Migration

  def change do
    drop table(:runs)
    drop table(:mappings)

    create table(:sources) do
      add :connection_id, references(:connections, on_delete: :restrict), null: false
      add :repo, :string, null: false
      add :interval_seconds, :integer, null: false, default: 3600
      add :enabled, :boolean, null: false, default: true
      add :webhook_secret, :binary
      add :webhook_id, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:sources, [:connection_id, :repo])

    create table(:destinations) do
      add :source_id, references(:sources, on_delete: :delete_all), null: false
      add :connection_id, references(:connections, on_delete: :restrict), null: false
      add :repo, :string, null: false
      add :enabled, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:destinations, [:source_id])
    create unique_index(:destinations, [:connection_id, :repo])

    create table(:runs) do
      add :source_id, references(:sources, on_delete: :delete_all), null: false
      add :status, :string, null: false
      add :started_at, :utc_datetime, null: false
      add :finished_at, :utc_datetime
      add :log, :text

      timestamps(type: :utc_datetime)
    end

    create index(:runs, [:source_id, :started_at])

    create table(:run_targets) do
      add :run_id, references(:runs, on_delete: :delete_all), null: false
      add :destination_id, references(:destinations, on_delete: :delete_all), null: false
      add :status, :string, null: false
      add :refs_pushed, {:array, :string}
      add :log, :text

      timestamps(type: :utc_datetime)
    end

    create index(:run_targets, [:run_id])
  end
end
