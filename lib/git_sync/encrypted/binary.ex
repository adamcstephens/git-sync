defmodule GitSync.Encrypted.Binary do
  @moduledoc false

  use Cloak.Ecto.Binary, vault: GitSync.Vault
end
