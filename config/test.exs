use Mix.Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :loginservice, LoginserviceWeb.Endpoint,
  http: [port: 4001],
  server: false

config :loginservice, Loginservice.Interfaces.Mail,
   mail_service: :consoleout

# Print only warnings and errors during test
config :logger, level: :warn

# Configure your database
config :loginservice, Loginservice.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: System.get_env("DB_USER") || "postgres",
  password: System.get_env("DB_PASSWORD") || "postgres",
  database: System.get_env("DB_DATABASE") || "loginservice_test",
  hostname: System.get_env("DB_HOSTNAME") || "postgres-loginservice",
  pool: Ecto.Adapters.SQL.Sandbox

# Speed up tests by reducing encryption rounds
# Unfortunately this doesn't work
#config :comeonin, :bcrypt_log_rounds, 4
#config :comeonin, :pbkdf2_rounds, 1 