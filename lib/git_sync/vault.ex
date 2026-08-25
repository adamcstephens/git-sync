defmodule GitSync.Vault do
  @moduledoc """
  Cloak vault backing the encrypted credential fields on `GitSync.Connection`.
  """

  use Cloak.Vault, otp_app: :git_sync
end
