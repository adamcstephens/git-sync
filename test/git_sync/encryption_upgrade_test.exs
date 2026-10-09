defmodule GitSync.EncryptionUpgradeTest do
  use ExUnit.Case, async: false

  alias GitSync.UpgradeRepo

  @version 20_261_009_025_209
  @columns ["token", "refresh_token", "ssh_key", "client_secret"]
  @migrations (for file <- Path.wildcard(Path.expand("../../priv/repo/migrations/*.exs", __DIR__)) do
                 [version, name] = String.split(Path.basename(file, ".exs"), "_", parts: 2)
                 module = Module.concat(GitSync.Repo.Migrations, Macro.camelize(name))
                 unless Code.ensure_loaded?(module), do: Code.compile_file(file)
                 {String.to_integer(version), module}
               end)

  setup do
    database =
      Path.join(System.tmp_dir!(), "git-sync-upgrade-#{System.unique_integer([:positive])}.db")

    start_supervised!({UpgradeRepo, database: database, pool_size: 1})

    on_exit(fn ->
      for suffix <- ["", "-wal", "-shm"], do: File.rm(database <> suffix)
    end)

    Ecto.Migrator.run(UpgradeRepo, @migrations, :up, to: @version - 1, log: false)
    :ok
  end

  test "converts every credential, preserves nulls and payloads, and runs only once" do
    old = legacy_encrypt("credential\nwith bytes\0")
    insert_connection(old)

    UpgradeRepo.query!(
      "INSERT INTO sources (connection_id, repo, interval_seconds, enabled, webhook_secret, inserted_at, updated_at) VALUES (1, 'repo', 60, 0, ?, datetime('now'), datetime('now'))",
      [old]
    )

    assert Ecto.Migrator.run(UpgradeRepo, @migrations, :up, all: true, log: false) == [@version]

    %{rows: [values]} =
      UpgradeRepo.query!(
        "SELECT token, refresh_token, ssh_key, client_secret FROM connections WHERE id = 1"
      )

    for value <- values do
      assert Fields.AES.decrypt(value) == "credential\nwith bytes\0"
      assert value == "0000" <> binary_part(old, 12, byte_size(old) - 12)
    end

    assert %{rows: [[nil, nil, nil, nil]]} =
             UpgradeRepo.query!(
               "SELECT token, refresh_token, ssh_key, client_secret FROM connections WHERE id = 2"
             )

    assert %{rows: [[secret]]} = UpgradeRepo.query!("SELECT webhook_secret FROM sources")
    assert secret == hd(values)
    assert Ecto.Migrator.run(UpgradeRepo, @migrations, :up, all: true, log: false) == []

    assert %{rows: [^values]} =
             UpgradeRepo.query!(
               "SELECT token, refresh_token, ssh_key, client_secret FROM connections WHERE id = 1"
             )
  end

  test "authentication failure rolls back earlier updates and does not record the migration" do
    old = legacy_encrypt("valid")
    insert_connection(old)
    bad = legacy_encrypt("invalid", :crypto.strong_rand_bytes(32))
    UpgradeRepo.query!("UPDATE connections SET token = ? WHERE id = 2", [bad])

    assert_raise Ecto.MigrationError, fn ->
      Ecto.Migrator.run(UpgradeRepo, @migrations, :up, all: true, log: false)
    end

    assert %{rows: [[^old]]} = UpgradeRepo.query!("SELECT token FROM connections WHERE id = 1")
    refute @version in Ecto.Migrator.migrated_versions(UpgradeRepo)
  end

  test "a fresh database can migrate and store Fields credentials" do
    Ecto.Migrator.run(UpgradeRepo, @migrations, :up, all: true, log: false)
    encrypted = Fields.AES.encrypt("")

    UpgradeRepo.query!(
      "INSERT INTO connections (kind, base_url, token, inserted_at, updated_at) VALUES ('github', 'https://example.com', ?, datetime('now'), datetime('now'))",
      [encrypted]
    )

    assert %{rows: [[value]]} = UpgradeRepo.query!("SELECT token FROM connections")
    assert Fields.AES.decrypt(value) == ""
  end

  test "the credential type rejects failed authentication" do
    good = Fields.AES.encrypt("secret")
    <<prefix::binary-size(36), first, rest::binary>> = good
    assert GitSync.Encrypted.Binary.load(good) == {:ok, "secret"}

    assert GitSync.Encrypted.Binary.load(prefix <> <<Bitwise.bxor(first, 1), rest::binary>>) ==
             :error
  end

  defp insert_connection(value) do
    columns = Enum.join(@columns, ", ")

    UpgradeRepo.query!(
      "INSERT INTO connections (id, kind, base_url, #{columns}, inserted_at, updated_at) VALUES (1, 'github', 'https://example.com', ?, ?, ?, ?, datetime('now'), datetime('now'))",
      List.duplicate(value, 4)
    )

    UpgradeRepo.query!(
      "INSERT INTO connections (id, kind, base_url, inserted_at, updated_at) VALUES (2, 'tangled', 'https://example.com', datetime('now'), datetime('now'))"
    )
  end

  defp legacy_encrypt(
         value,
         key \\ Base.decode64!(Application.fetch_env!(:fields, :encryption_keys))
       ) do
    iv = :crypto.strong_rand_bytes(16)
    {body, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, value, "AES256GCM", true)
    <<1, 10>> <> "AES.GCM.V1" <> iv <> tag <> body
  end
end
