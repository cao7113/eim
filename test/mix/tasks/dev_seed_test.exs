defmodule Mix.Tasks.Dev.SeedTest do
  use Eim.DataCase, async: false

  require Ash.Query

  alias Eim.Accounts.{Admins, User}

  setup do
    original_env = Mix.env()
    original_shell = Mix.shell()
    Mix.env(:dev)
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.env(original_env)
      Mix.shell(original_shell)
    end)

    :ok
  end

  test "creates development users and is repeatable" do
    Mix.Tasks.Dev.Seed.run([])
    admin = user_by_email!("admin@l.h")
    user = user_by_email!("dev@l.h")
    assert Admins.admin?(admin.id)
    refute Admins.admin?(user.id)

    assert Repo.aggregate(from(e in "audit_events"), :count) == 1
    Mix.Tasks.Dev.Seed.run([])
    assert Admins.admin?(user_by_email!("admin@l.h").id)
    assert Repo.aggregate(from(e in "audit_events"), :count) == 1
  end

  test "grants the role when another administrator exists" do
    existing = Ash.Seed.seed!(User, %{email: "existing-admin@l.h"})

    assert {:ok, _} = Admins.bootstrap("existing-admin@l.h")
    Mix.Tasks.Dev.Seed.run([])
    admin = user_by_email!("admin@l.h")
    assert Admins.admin?(admin.id)

    assert Repo.exists?(
             from e in "audit_events",
               where:
                 e.actor_id == ^Ecto.UUID.dump!(existing.id) and
                   e.subject_id == ^Ecto.UUID.dump!(admin.id) and e.event_type == "admin.granted"
           )
  end

  test "the task refuses to run outside development" do
    Mix.env(:test)

    assert_raise Mix.Error, "mix dev.seed can only be run in the dev environment", fn ->
      Mix.Tasks.Dev.Seed.run([])
    end
  end

  defp user_by_email!(email) do
    {:ok, user} =
      User
      |> Ash.Query.filter(email == ^email)
      |> Ash.read_one(domain: Eim.Accounts, authorize?: false)

    user
  end
end
