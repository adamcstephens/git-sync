defmodule GitSync.Repo.Migrations.AddWebhookToMappings do
  use Ecto.Migration

  def change do
    alter table(:mappings) do
      add :webhook_secret, :binary
      add :webhook_id, :string
    end
  end
end
