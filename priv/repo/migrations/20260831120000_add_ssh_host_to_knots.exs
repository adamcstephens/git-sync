defmodule GitSync.Repo.Migrations.AddSshHostToKnots do
  use Ecto.Migration

  def change do
    alter table(:knots) do
      add :ssh_host, :string
    end

    execute "UPDATE knots SET ssh_host = host", ""
  end
end
