defmodule Eim.Accounts.OidcIdentityTest do
  use Eim.DataCase, async: false

  require Ash.Query

  alias Eim.Accounts.User
  alias Eim.Accounts.UserIdentity

  test "registers the same Authx subject as the same local user" do
    assert {:ok, user} = register("authx-sub-1", "person@example.com")
    assert to_string(user.email) == "person@example.com"

    assert {:ok, same_user} = register("authx-sub-1", "person@example.com")
    assert same_user.id == user.id

    assert {:ok, identity} = identity_for("authx-sub-1")
    assert identity.strategy == "authx"
    assert identity.user_id == user.id
    assert to_string(user.email) == "person@example.com"
  end

  test "links an existing local user with the same verified email" do
    existing = Ash.Seed.seed!(User, %{email: "existing@example.com"})

    assert {:ok, user} = register("authx-sub-2", "existing@example.com")
    assert user.id == existing.id

    assert {:ok, identity} = identity_for("authx-sub-2")
    assert identity.user_id == existing.id
  end

  test "refuses to link a second Authx subject to an already linked email" do
    assert {:ok, user} = register("authx-sub-3", "shared@example.com")
    assert {:error, _reason} = register("authx-sub-4", "shared@example.com")

    assert {:ok, users} = Ash.read(User, domain: Eim.Accounts, authorize?: false)
    assert Enum.count(users, &(&1.id == user.id)) == 1
    assert length(users) == 1
    assert {:ok, nil} = identity_for("authx-sub-4")
  end

  defp register(sub, email) do
    User
    |> Ash.Changeset.for_create(
      :register_with_authx,
      %{
        user_info: %{"sub" => sub, "email" => email, "email_verified" => true},
        oauth_tokens: %{"access_token" => "test-token"}
      },
      authorize?: false
    )
    |> Ash.create(domain: Eim.Accounts, authorize?: false)
  end

  defp identity_for(sub) do
    UserIdentity
    |> Ash.Query.filter(uid == ^sub and strategy == "authx")
    |> Ash.read_one(domain: Eim.Accounts, authorize?: false)
  end
end
