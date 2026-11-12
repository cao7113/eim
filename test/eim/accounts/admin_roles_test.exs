defmodule Eim.Accounts.AdminRolesTest do
  use Eim.DataCase, async: false

  alias Eim.Accounts.User
  alias Eim.Accounts.Admins, as: AdminRoles
  alias Eim.Audit.Event

  test "bootstraps once, authorizes changes against the database, and protects the last admin" do
    alice = create_user("alice@example.com")
    bob = create_user("bob@example.com")
    assert alice.role == :user

    assert {:error, :forbidden} = AdminRoles.set_role(alice.id, bob.id, :admin)
    assert {:error, :user_not_found} = AdminRoles.bootstrap("missing@example.com")
    assert {:ok, %{role: :admin}} = AdminRoles.bootstrap("ALICE@example.com")
    assert {:error, :already_bootstrapped} = AdminRoles.bootstrap("bob@example.com")
    assert {:error, :already_bootstrapped} = AdminRoles.bootstrap("missing@example.com")
    assert {:error, :last_admin} = AdminRoles.set_role(alice.id, alice.id, :user)
    assert {:ok, %{role: :admin}} = AdminRoles.set_role(alice.id, bob.id, :admin)
    assert {:ok, %{role: :user}} = AdminRoles.set_role(bob.id, alice.id, :user)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.read(Event, actor: alice, authorize?: true, authorize_with: :error)

    assert {:error, :forbidden} = AdminRoles.set_role(alice.id, bob.id, :user)
    assert {:error, :last_admin} = AdminRoles.set_role(bob.id, bob.id, :user)

    changes = Repo.all(from c in "audit_events", select: {c.event_type, c.details})

    assert Enum.sort(changes) ==
             Enum.sort([
               {"admin.granted",
                %{"method" => "bootstrap", "old_role" => "user", "new_role" => "admin"}},
               {"admin.granted",
                %{"method" => "admin", "old_role" => "user", "new_role" => "admin"}},
               {"admin.revoked",
                %{"method" => "admin", "old_role" => "admin", "new_role" => "user"}}
             ])

    events = Repo.all(from c in "audit_events", select: {c.actor_id, c.subject_id, c.event_type})
    alice_id = Ecto.UUID.dump!(alice.id)
    bob_id = Ecto.UUID.dump!(bob.id)

    assert {nil, alice_id, "admin.granted"} in events
    assert {alice_id, bob_id, "admin.granted"} in events
    assert {bob_id, alice_id, "admin.revoked"} in events
  end

  test "registration cannot grant the administrator role" do
    changeset =
      Ash.Changeset.for_create(User, :register_with_password, %{
        email: "new@example.com",
        password: "password123456",
        password_confirmation: "password123456",
        role: :admin
      })

    refute changeset.valid?
  end

  test "Ash policies protect direct role, bootstrap, search and audit actions" do
    alice = create_user("alice-policy@example.com")
    bob = create_user("bob-policy@example.com")
    assert {:ok, _} = AdminRoles.bootstrap("alice-policy@example.com")

    assert {:error, %Ash.Error.Forbidden{}} =
             bob
             |> Ash.Changeset.for_update(:set_admin_role, %{role: :admin}, actor: bob)
             |> Ash.update(actor: bob, authorize?: true)

    assert {:error, %Ash.Error.Forbidden{}} =
             bob
             |> Ash.Changeset.for_update(:set_admin_role, %{role: :admin})
             |> Ash.update(authorize?: true)

    assert {:error, %Ash.Error.Forbidden{}} =
             bob
             |> Ash.Changeset.for_update(:bootstrap_admin, %{}, actor: alice)
             |> Ash.update(actor: alice, authorize?: true)

    assert {:error, %Ash.Error.Forbidden{}} =
             AdminRoles.find_by_email(bob, "alice-policy@example.com")

    assert {:error, %Ash.Error.Forbidden{}} =
             Event
             |> Ash.Changeset.for_create(
               :record,
               %{
                 actor_id: bob.id,
                 event_type: "admin.granted",
                 subject_type: "user",
                 subject_id: bob.id,
                 details: %{old_role: :user, new_role: :admin, method: :admin}
               },
               actor: bob
             )
             |> Ash.create(actor: bob, authorize?: true)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.read(Event, actor: bob, authorize?: true, authorize_with: :error)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.read(Event, authorize?: true, authorize_with: :error)

    assert is_nil(Ash.Resource.Info.action(Event, :update))
    assert is_nil(Ash.Resource.Info.action(Event, :destroy))
  end

  test "get_by_email_as_admin returns any matching user only to an administrator" do
    alice = create_user("alice-search@example.com")
    bob = create_user("bob-search@example.com")
    assert {:ok, admin} = AdminRoles.bootstrap("alice-search@example.com")

    query = Ash.Query.for_read(User, :get_by_email_as_admin, %{email: "BOB-search@example.com"})
    assert {:ok, %{id: id, role: :user}} = Ash.read_one(query, actor: admin, authorize?: true)
    assert id == bob.id

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.read_one(query, actor: bob, authorize?: true, authorize_with: :error)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.read_one(query, authorize?: true, authorize_with: :error)

    assert alice.id == admin.id
  end

  test "fresh database roles override stale actor and target records" do
    alice = create_user("alice-stale@example.com")
    bob = create_user("bob-stale@example.com")
    assert {:ok, alice_admin} = AdminRoles.bootstrap("alice-stale@example.com")
    assert {:ok, bob_admin} = AdminRoles.set_role(alice.id, bob.id, :admin)

    assert {:ok, %{role: :user}} =
             bob
             |> Ash.Changeset.for_update(:set_admin_role, %{role: :user}, actor: alice_admin)
             |> Ash.update(actor: alice_admin, authorize?: true)

    assert {:error, %Ash.Error.Forbidden{}} =
             alice_admin
             |> Ash.Changeset.for_update(:set_admin_role, %{role: :user}, actor: bob_admin)
             |> Ash.update(actor: bob_admin, authorize?: true)

    assert {:ok, changes} = Ash.read(Event, actor: alice_admin, authorize?: true)

    assert Enum.any?(
             changes,
             &(&1.subject_id == bob.id and &1.details["old_role"] == "admin" and
                 &1.details["new_role"] == "user")
           )
  end

  test "a failed audit write rolls back the role update" do
    alice = create_user("alice-rollback@example.com")
    bob = create_user("bob-rollback@example.com")
    assert {:ok, _} = AdminRoles.bootstrap("alice-rollback@example.com")

    Ecto.Adapters.SQL.query!(
      Repo,
      "ALTER TABLE audit_events ADD CONSTRAINT test_no_admin_grant CHECK (event_type <> 'admin.granted') NOT VALID",
      []
    )

    assert {:error, _error} = AdminRoles.set_role(alice.id, bob.id, :admin)
    refute AdminRoles.admin?(bob.id)
  end

  test "setting an unchanged role does not create an audit record" do
    alice = create_user("alice-noop@example.com")
    bob = create_user("bob-noop@example.com")
    assert {:ok, _} = AdminRoles.bootstrap("alice-noop@example.com")
    assert {:ok, %{role: :user}} = AdminRoles.set_role(alice.id, bob.id, :user)
    assert Repo.aggregate(from(c in "audit_events"), :count) == 1
  end

  defp create_user(email) do
    {1, [%{id: id}]} =
      Repo.insert_all("users", [%{email: email, hashed_password: "test"}], returning: [:id])

    Repo.get!(User, id)
  end
end
