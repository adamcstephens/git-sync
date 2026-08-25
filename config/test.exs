import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :git_sync, GitSync.Repo,
  database: Path.expand("../git_sync_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :git_sync, GitSyncWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "CtIsP+TFusef/8LFQzkEk7cpbLMtJg0LhKnn2ulLuBrjBrpaJNr11EV/xsnv6HUN",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

config :git_sync, GitSync.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V1", key: Base.decode64!("aqk/Lo+yqt9cBQo0Pi4TPYgfP/8hC9axhT3DMJecN5I=")}
  ]

# Outbound HTTP is stubbed per test process; see `Req.Test`.
config :git_sync, :req_options, plug: {Req.Test, GitSync.Http}
