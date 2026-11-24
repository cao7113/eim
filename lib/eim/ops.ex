defmodule Eim.Ops do
  @moduledoc """
  Operational entry points for trusted IEx sessions and mix tasks.

  Emails identify an `Eim.Accounts.User`. Bootstrap grants administrator access
  without an actor, so it bypasses Ash policies: the only protection is the
  trust placed in operational shell access.

  Never call this module from the web application.
  """

  alias Eim.Accounts
  alias Eim.Accounts.User
  alias Eim.Admins

  @doc """
  Grants administrator access to the user identified by `user_ref`.

  Returns `{:ok, admin}` on success, or `{:error, reason}` on failure.
  """
  def bootstrap_admin(user_ref) when is_binary(user_ref) do
    with {:ok, %User{} = user} <- Accounts.fetch_user_by_ref(user_ref) do
      Admins.bootstrap_admin(user)
    else
      {:ok, nil} -> {:error, :user_not_found}
      error -> error
    end
  end

  def bootstrap_master_admin do
    Admins.master_email()
    |> bootstrap_admin()
  end
end
