defmodule Eim.Accounts.AdminRolesConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Eim.Accounts.User
  alias Eim.Accounts.Admins, as: AdminRoles
  alias Eim.Repo
  alias Ecto.Adapters.SQL.Sandbox

  test "concurrent administrators cannot revoke each other" do
    supervisor = start_supervised!(Task.Supervisor)
    test_id = Ecto.UUID.generate()
    alice_id = Ecto.UUID.generate()
    bob_id = Ecto.UUID.generate()
    ids = [Ecto.UUID.dump!(alice_id), Ecto.UUID.dump!(bob_id)]

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(from c in "audit_events", where: c.subject_id in ^ids)
        Repo.delete_all(from u in "users", where: u.id in ^ids)
      end)
    end)

    Sandbox.unboxed_run(Repo, fn ->
      refute Repo.exists?(from u in User, where: u.role == :admin)

      Repo.insert_all("users", [
        %{
          id: Ecto.UUID.dump!(alice_id),
          email: "alice-#{test_id}@example.com",
          hashed_password: "test",
          role: "admin"
        },
        %{
          id: Ecto.UUID.dump!(bob_id),
          email: "bob-#{test_id}@example.com",
          hashed_password: "test",
          role: "admin"
        }
      ])
    end)

    parent = self()

    tasks =
      for {actor_id, target_id} <- [{alice_id, bob_id}, {bob_id, alice_id}] do
        Task.Supervisor.async_nolink(supervisor, fn ->
          Sandbox.unboxed_run(Repo, fn ->
            send(parent, {:ready, self()})
            receive do: (:go -> AdminRoles.set_role(actor_id, target_id, :user))
          end)
        end)
      end

    ready =
      for _ <- tasks do
        assert_receive {:ready, pid}
        pid
      end

    Enum.each(ready, &send(&1, :go))

    results = Enum.map(tasks, &Task.await(&1, 15_000))
    assert Enum.count(results, &match?({:ok, %{role: :user}}, &1)) == 1
    assert Enum.count(results, &match?({:error, :forbidden}, &1)) == 1

    Sandbox.unboxed_run(Repo, fn ->
      assert Repo.aggregate(
               from(u in User, where: u.id in ^[alice_id, bob_id] and u.role == :admin),
               :count
             ) == 1
    end)
  end
end
