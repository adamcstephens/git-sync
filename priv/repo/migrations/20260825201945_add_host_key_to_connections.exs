defmodule GitSync.Repo.Migrations.AddHostKeyToConnections do
  use Ecto.Migration

  def change do
    alter table(:connections) do
      add :host_key, :string
    end
  end
end
