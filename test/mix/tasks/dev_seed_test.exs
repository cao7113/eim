defmodule Mix.Tasks.Dev.SeedTest do
  use Eim.DataCase, async: false

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

  test "creates confirmed users with the development password and is repeatable" do
    Mix.Tasks.Dev.Seed.run([])
    admin = sign_in!("admin@l.h")
    user = sign_in!("dev@l.h")
    assert Admins.admin?(admin.id)
    refute Admins.admin?(user.id)

    assert Repo.aggregate(from(e in "audit_events"), :count) == 1
    Mix.Tasks.Dev.Seed.run([])
    assert Admins.admin?(sign_in!("admin@l.h").id)
    assert Repo.aggregate(from(e in "audit_events"), :count) == 1
  end

  test "grants the role when another administrator exists" do
    existing =
      Ash.Seed.seed!(User, %{email: "existing-admin@l.h", hashed_password: "test"})

    assert {:ok, _} = Admins.bootstrap("existing-admin@l.h")
    Mix.Tasks.Dev.Seed.run([])
    admin = sign_in!("admin@l.h")
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

  defp sign_in!(email) do
    strategy = AshAuthentication.Info.strategy!(User, :password)

    assert {:ok, user} =
             AshAuthentication.Strategy.action(strategy, :sign_in, %{
               email: email,
               password: "password123456"
             })

    user
  end
end
