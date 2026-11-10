import Config

config :eim, Oban, testing: :manual
config :eim, token_signing_secret: "3M2JdqCyRDf0dC0CnwRn7Wj6zET/z4je"
config :bcrypt_elixir, log_rounds: 1

config :ash,
  policies: [show_policy_breakdowns?: true],
  keyset_signing_secret: "n0S3lQqN+L+HIV4QJZ75+SW3hI0MzyD2K1W6O5KJ8UI",
  disable_async?: true

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :eim, Eim.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "eim_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :eim, EimWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Ew+KH4Yr6R9+Cruvz2oj0sSihocUyx/RP/Xtqm8KucgMyHP2PhjiN4PZsjWIILmb",
  server: false

# In test we don't send emails
config :eim, Eim.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

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
