defmodule Eim.Repo.Migrations.AddUserRole do
  @moduledoc "Adds administrator roles and management event history."

  use Ecto.Migration

  def up do
    alter table(:users) do
      add :role, :text, null: false, default: "user"
    end

    create constraint(:users, :users_role_valid, check: "role IN ('user', 'admin')")

    create table(:audit_events, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :event_type, :text, null: false
      add :actor_id, :uuid
      add :subject_type, :text, null: false
      add :subject_id, :uuid, null: false
      add :details, :map, null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create index(:audit_events, [:inserted_at, :id])
    create index(:audit_events, [:event_type, :inserted_at, :id])
    create index(:audit_events, [:subject_type, :subject_id, :inserted_at, :id])
  end

  def down do
    drop table(:audit_events)
    drop constraint(:users, :users_role_valid)

    alter table(:users) do
      remove :role
    end
  end
end
