defmodule GitSync.Repo.Migrations.AddTokenRefreshToConnections do
  use Ecto.Migration

  def change do
    alter table(:connections) do
      add :refresh_token, :binary
      add :token_expires_at, :utc_datetime
      add :subject, :string
    end
  end
end
