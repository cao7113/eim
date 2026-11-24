defmodule Eim.Repo.Migrations.AddAdmins do
  @moduledoc """
  Adds administrator access records, backfills the existing role assignments and
  drops `users.role`.

  Access is stored per user in `admins`, so no registration or upsert path on
  `users` can grant it. The backfill keeps existing administrators: their
  `granted_at` is the migration timestamp because the original grant time is not
  recorded, and `granted_by_user_id` stays empty because the granting operator is
  unknown — the same shape a bootstrap grant has.

  `down/0` restores the role column from the rows that are still present, but it
  cannot restore grants that were withdrawn in the meantime. Withdrawing access
  is not implemented yet, so no such history exists today.
  """

  use Ecto.Migration

  def up do
    create table(:admins, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :granted_by_user_id, references(:users, type: :uuid, on_delete: :nilify_all)

      add :granted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:admins, [:user_id])

    execute("""
    INSERT INTO #{qualified(:admins)} (id, user_id, granted_at, inserted_at, updated_at)
    SELECT gen_random_uuid(), id, now(), now(), now()
    FROM #{qualified(:users)}
    WHERE role = 'admin'
    """)

    drop constraint(:users, :users_role_valid)

    alter table(:users) do
      remove :role
    end
  end

  def down do
    alter table(:users) do
      add :role, :text, null: false, default: "user"
    end

    create constraint(:users, :users_role_valid, check: "role IN ('user', 'admin')")

    execute("""
    UPDATE #{qualified(:users)}
    SET role = 'admin'
    WHERE id IN (SELECT user_id FROM #{qualified(:admins)})
    """)

    drop table(:admins)
  end

  # `execute/1` does not apply the migration prefix, so the table names are
  # qualified explicitly. Identifiers are static atoms, never user input.
  defp qualified(table) do
    name = Atom.to_string(table)

    case migration_prefix() do
      prefix when is_binary(prefix) and prefix != "" -> prefix <> "." <> name
      _ -> name
    end
  end

  # `Ecto.Migration.prefix/0` returns `nil` during ordinary migrations; the
  # rescue keeps this working if it is ever called outside a migration run.
  defp migration_prefix do
    Ecto.Migration.prefix()
  rescue
    _error -> nil
  end
end
