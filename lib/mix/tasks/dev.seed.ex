defmodule Mix.Tasks.Dev.Seed do
  use Mix.Task

  @shortdoc "Creates the confirmed development user"
  @moduledoc """
  Creates or updates the local development user.

  This task is only available in the dev environment.
  """

  @impl Mix.Task
  def run(_args) do
    unless Mix.env() == :dev do
      Mix.raise("mix dev.seed can only be run in the dev environment")
    end

    Mix.Task.run("app.start")

    {:ok, hashed_password} = AshAuthentication.BcryptProvider.hash("password123456")

    Ash.Seed.upsert!(
      Eim.Accounts.User,
      %{
        email: "dev@l.h",
        hashed_password: hashed_password,
        confirmed_at: DateTime.utc_now()
      },
      identity: :unique_email
    )

    Mix.shell().info("Development user dev@l.h is ready.")
  end
end
