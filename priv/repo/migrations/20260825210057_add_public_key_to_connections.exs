defmodule GitSync.Repo.Migrations.AddPublicKeyToConnections do
  use Ecto.Migration

  def change do
    alter table(:connections) do
      add :public_key, :string
    end
  end
end
