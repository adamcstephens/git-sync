defmodule GitSync.Repo.Migrations.AddAtprotoIdentityToConnections do
  use Ecto.Migration

  def change do
    alter table(:connections) do
      add :did, :string
      add :handle, :string
      add :pds_url, :string
    end
  end
end
