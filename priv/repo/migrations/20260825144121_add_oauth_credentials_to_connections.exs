defmodule GitSync.Repo.Migrations.AddOauthCredentialsToConnections do
  use Ecto.Migration

  def change do
    alter table(:connections) do
      add :client_id, :string
      add :client_secret, :binary
      add :operator, :string
    end
  end
end
