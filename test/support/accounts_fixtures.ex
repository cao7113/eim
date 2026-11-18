defmodule Eim.AccountsFixtures do
  @moduledoc """
  Test helpers for local users backed by an Authx identity.
  """

  alias Eim.Accounts.User

  def user_fixture(email) do
    user_info = %{
      "sub" => "test-#{email}-#{System.unique_integer([:positive])}",
      "email" => email,
      "email_verified" => true
    }

    {:ok, user} =
      User
      |> Ash.Changeset.for_create(
        :register_with_authx,
        %{
          user_info: user_info,
          oauth_tokens: %{"access_token" => "test-token"}
        },
        authorize?: false
      )
      |> Ash.create(domain: Eim.Accounts, authorize?: false)

    user
  end

  def signed_in_conn(user) do
    Phoenix.ConnTest.build_conn()
    |> Plug.Test.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end
end
