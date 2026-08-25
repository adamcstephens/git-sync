defmodule GitSync.Repo.Migrations.CreateRuns do
  use Ecto.Migration

  def change do
    create table(:runs) do
      add :mapping_id, references(:mappings, on_delete: :delete_all), null: false
      add :status, :string, null: false
      add :started_at, :utc_datetime, null: false
      add :finished_at, :utc_datetime
      add :refs_pushed, {:array, :string}
      add :log, :text

      timestamps(type: :utc_datetime)
    end

    create index(:runs, [:mapping_id, :started_at])
  end
end
