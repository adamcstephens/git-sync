defmodule GitSync.Repo do
  use Ecto.Repo,
    otp_app: :git_sync,
    adapter: Ecto.Adapters.SQLite3
end
