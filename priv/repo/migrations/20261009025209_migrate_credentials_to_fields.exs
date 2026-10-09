defmodule GitSync.Repo.Migrations.MigrateCredentialsToFields do
  use Ecto.Migration

  def up do
    migrate("connections", ["token", "refresh_token", "ssh_key", "client_secret"], 0)
    migrate("sources", ["webhook_secret"], 0)
  end

  def down do
    raise Ecto.MigrationError, "restore the pre-upgrade database backup to roll back encryption"
  end

  defp migrate(table, columns, after_id) do
    selected = Enum.join(["id" | columns], ", ")

    %{rows: rows} =
      repo().query!(
        "SELECT #{selected} FROM #{table} WHERE id > ? ORDER BY id LIMIT 100",
        [after_id],
        log: false
      )

    for [id | values] <- rows do
      converted = Enum.map(values, &convert(&1, table, id))
      assignments = Enum.map_join(columns, ", ", &"#{&1} = ?")

      repo().query!(
        "UPDATE #{table} SET #{assignments} WHERE id = ?",
        converted ++ [id],
        log: false
      )
    end

    case List.last(rows) do
      nil -> :ok
      [id | _] -> migrate(table, columns, id)
    end
  end

  defp convert(nil, _table, _id), do: nil

  defp convert(<<1, 10, "AES.GCM.V1", payload::binary>>, table, id) do
    converted = "0000" <> payload

    case Fields.AES.decrypt(converted) do
      plaintext when is_binary(plaintext) ->
        converted

      :error ->
        raise Ecto.MigrationError, "credential authentication failed in #{table} row #{id}"
    end
  end

  defp convert(_value, table, id) do
    raise Ecto.MigrationError, "unexpected credential format in #{table} row #{id}"
  end
end
