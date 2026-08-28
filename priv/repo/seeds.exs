# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     GitSync.Repo.insert!(%GitSync.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# A development database is seeded with a mirror that runs against bare
# repositories on disk, so a dev instance holds no real credential. The module
# only exists where :dev_routes is set.
if Application.get_env(:git_sync, :dev_routes) do
  GitSync.DevSeeds.seed()
end
