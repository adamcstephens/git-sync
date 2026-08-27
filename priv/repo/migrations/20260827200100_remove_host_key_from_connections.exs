defmodule GitSync.Repo.Migrations.RemoveHostKeyFromConnections do
  use Ecto.Migration

  def change do
    alter table(:connections) do
      remove :host_key, :string
    end
  end
end
