import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
# config :vm_monitoring, VmMonitoring.Repo,
#   # username: "postgres",
#   # password: "postgres",
#   # hostname: "localhost",
#   # database: "vm_monitoring_test#{System.get_env("MIX_TEST_PARTITION")}",
#   pool: Ecto.Adapters.SQL.Sandbox,
#   database: "priv/repo/vm_monitoring.db",
  # pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :vm_monitoring, VmMonitoringWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "6kP76JJoYj3VW+S6W+0H7wPZiE1AqNQquHYtW+H1RDv/QAFOZJ2q94tMSTmKWV80",
  server: false

# In test we don't send emails
config :vm_monitoring, VmMonitoring.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
