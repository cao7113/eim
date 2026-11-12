defmodule Mix.Tasks.Dev.Seed do
  use Mix.Task

  require Ash.Query

  alias Eim.Accounts.{Admins, User}

  @user_email "dev@l.h"
  @admin_email "admin@l.h"
  @password "password123456"

  @shortdoc "Creates confirmed development and administrator users"
  @moduledoc """
  Creates or updates #{@user_email} and the administrator #{@admin_email}, both
  with the local development password #{@password}.

  This task is only available in the dev environment.
  """

  @impl Mix.Task
  def run(_args) do
    unless Mix.env() == :dev do
      Mix.raise("mix dev.seed can only be run in the dev environment")
    end

    Mix.Task.run("app.start")

    {:ok, hashed_password} = AshAuthentication.BcryptProvider.hash(@password)

    seed_user!(@user_email, hashed_password)
    admin = seed_user!(@admin_email, hashed_password)
    ensure_admin!(admin.id)

    Mix.shell().info("Development users #{@user_email} and #{@admin_email} are ready.")
  end

  defp seed_user!(email, hashed_password) do
    Ash.Seed.upsert!(
      User,
      %{email: email, hashed_password: hashed_password, confirmed_at: DateTime.utc_now()},
      identity: :unique_email
    )
  end

  defp ensure_admin!(id) do
    if not Admins.admin?(id) do
      result =
        User
        |> Ash.Query.filter(role == :admin)
        |> Ash.Query.limit(1)
        |> Ash.read_one(domain: Eim.Accounts, authorize?: false)

      case result do
        {:ok, nil} ->
          check_role_result!(Admins.bootstrap(@admin_email))

        {:ok, actor} ->
          check_role_result!(Admins.set_role(actor.id, id, :admin))

        {:error, error} ->
          Mix.raise("Could not find an existing administrator: #{inspect(error)}")
      end
    end
  end

  defp check_role_result!({:ok, _user}), do: :ok

  defp check_role_result!({:error, error}) do
    Mix.raise("Could not grant the development administrator role: #{inspect(error)}")
  end
end
