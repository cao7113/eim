defmodule Eim.AdminsTest do
  use Eim.DataCase, async: false

  alias Eim.Accounts.User
  alias Eim.Admins
  alias Eim.Admins.Admin
  alias Eim.Ops

  test "bootstrap grants access once and records an audit event" do
    alice = create_user("alice@example.com")

    refute Admins.admin?(alice)
    refute Admins.admin?(alice.id)

    assert {:ok, %Admin{id: admin_id, granted_by_user_id: nil}} = Admins.bootstrap_admin(alice)
    assert Admins.admin?(alice)
    assert Admins.admin?(alice.id)

    # Booting an existing administrator is idempotent: same record, one event.
    assert {:ok, %Admin{id: ^admin_id}} = Admins.bootstrap_admin(alice)
    assert {:ok, %Admin{user_id: alice_id}} = Ops.bootstrap_admin("ALICE@example.com")
    assert alice_id == alice.id

    assert [{"admin.granted", nil, subject_id, details}] =
             Repo.all(
               from(e in "audit_events",
                 select: {e.event_type, e.actor_id, e.subject_id, e.details}
               )
             )

    assert subject_id == Ecto.UUID.dump!(alice.id)

    assert details == %{
             "method" => "bootstrap",
             "new_role" => "admin",
             "old_role" => "user"
           }
  end

  test "grant_admin requires a current administrator" do
    alice = create_user("alice-grant@example.com")
    bob = create_user("bob-grant@example.com")
    assert {:ok, _admin} = Admins.bootstrap_admin(alice)

    assert {:error, %Ash.Error.Forbidden{}} = Admins.grant_admin(bob, bob)
    refute Admins.admin?(bob)

    assert {:ok, %Admin{granted_by_user_id: granted_by}} = Admins.grant_admin(bob, alice)
    assert granted_by == alice.id
    assert Admins.admin?(bob)

    assert [{"admin.granted", actor_id, _subject_id, %{"method" => "admin"}}] =
             Repo.all(
               from(e in "audit_events",
                 where: e.subject_id == ^Ecto.UUID.dump!(bob.id),
                 select: {e.event_type, e.actor_id, e.subject_id, e.details}
               )
             )

    assert actor_id == Ecto.UUID.dump!(alice.id)
  end

  test "Ash actions cannot grant access without an administrator actor" do
    bob = create_user("bob-policy@example.com")

    assert {:error, %Ash.Error.Forbidden{}} =
             Admin
             |> Ash.Changeset.for_create(:grant, %{user_id: bob.id})
             |> Ash.create(domain: Eim.Admins.Domain, authorize?: true)

    assert {:error, %Ash.Error.Forbidden{}} =
             Admin
             |> Ash.Changeset.for_create(:grant, %{user_id: bob.id}, actor: bob)
             |> Ash.create(domain: Eim.Admins.Domain, actor: bob, authorize?: true)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.read(Admin, actor: bob, authorize?: true, authorize_with: :error)

    refute Admins.admin?(bob)

    # Access can only be written through :grant; there is no update or destroy
    # action that could bypass the audit trail.
    assert is_nil(Ash.Resource.Info.action(Admin, :update))
    assert is_nil(Ash.Resource.Info.action(Admin, :destroy))
  end

  test "OIDC registration cannot grant administrator access" do
    {:ok, user} =
      User
      |> Ash.Changeset.for_create(
        :register_with_authx,
        %{
          user_info: %{
            "sub" => "new-authx-sub",
            "email" => "new@example.com",
            "role" => "admin"
          },
          oauth_tokens: %{}
        },
        authorize?: false
      )
      |> Ash.create(domain: Eim.Accounts, authorize?: false)

    refute Admins.admin?(user)
    assert {:error, :not_admin} = Admins.fetch_admin_by_user_ref(user.id)
  end

  test "a failed audit write rolls back the grant" do
    alice = create_user("alice-rollback@example.com")
    bob = create_user("bob-rollback@example.com")
    assert {:ok, _admin} = Admins.bootstrap_admin(alice)

    Ecto.Adapters.SQL.query!(
      Repo,
      "ALTER TABLE audit_events ADD CONSTRAINT test_no_admin_grant CHECK (event_type <> 'admin.granted') NOT VALID",
      []
    )

    assert {:error, _error} = Admins.grant_admin(bob, alice)
    refute Admins.admin?(bob)
  end

  test "admin? is false for missing or malformed references" do
    bob = create_user("bob-not-admin@example.com")

    refute Admins.admin?(nil)
    refute Admins.admin?("missing@example.com")
    refute Admins.admin?(Ecto.UUID.generate())
    refute Admins.admin?("not-a-uuid")
    refute Admins.admin?(bob)
    refute Admins.admin?(bob.id)

    assert {:error, :not_found_user} = Admins.fetch_admin_by_user_ref("missing@example.com")
    assert {:error, :not_found_user} = Admins.fetch_admin_by_user_ref("not-a-uuid")
    assert {:error, :not_found_user} = Admins.fetch_admin_by_user_ref(Ecto.UUID.generate())
    assert {:error, :not_admin} = Admins.fetch_admin_by_user_ref(bob)
    assert {:error, :not_admin} = Admins.fetch_admin_by_user_ref(bob.id)

    assert is_nil(Admins.get_admin_by_user_ref(nil))
    assert is_nil(Admins.get_admin_by_user_ref(bob))
    assert is_nil(Admins.get_admin_user(bob))
  end

  test "master_email/0 and master/0 report the configured administrator" do
    assert Admins.master_email() == "admin@l.h"
    assert is_nil(Admins.master())

    master = create_user("admin@l.h")
    # The account exists locally but is not an administrator yet.
    assert is_nil(Admins.master())
    assert is_nil(Admins.get_admin_user("admin@l.h"))

    assert {:ok, _admin} = Admins.bootstrap_admin(master)

    assert %User{id: master_id} = Admins.master()
    assert master_id == master.id
  end

  test "list/1 returns administrator records" do
    alice = create_user("alice-list@example.com")

    assert {:ok, []} = Admins.list()
    assert {:ok, _admin} = Admins.bootstrap_admin(alice)

    assert {:ok, [%Admin{user_id: user_id}]} = Admins.list()
    assert user_id == alice.id
  end

  defp create_user(email), do: Eim.AccountsFixtures.user_fixture(email)
end
