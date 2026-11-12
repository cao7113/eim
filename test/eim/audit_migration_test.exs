Code.require_file("../../priv/repo/migrations/20261111130110_add_user_role.exs", __DIR__)

defmodule Eim.AuditMigrationTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox
  alias Eim.Repo
  alias Eim.Repo.Migrations.AddUserRole

  test "a fresh migration creates roles and events without a legacy table" do
    schema = "audit_test_" <> String.replace(Ecto.UUID.generate(), "-", "")

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        SQL.query!(Repo, ~s(DROP SCHEMA IF EXISTS "#{schema}" CASCADE), [])
      end)
    end)

    Sandbox.mode(Repo, :auto)

    try do
      SQL.query!(Repo, ~s(CREATE SCHEMA "#{schema}"), [])
      SQL.query!(Repo, ~s|CREATE TABLE "#{schema}".users (id uuid PRIMARY KEY)|, [])

      assert :ok =
               Ecto.Migrator.up(Repo, 20_261_111_130_110, AddUserRole,
                 prefix: schema,
                 log: false
               )

      assert %{rows: [[true, false]]} =
               SQL.query!(
                 Repo,
                 "SELECT to_regclass($1) IS NOT NULL, to_regclass($2) IS NOT NULL",
                 ["#{schema}.audit_events", "#{schema}.user_role_changes"]
               )

      assert %{rows: [["user"]]} =
               SQL.query!(
                 Repo,
                 ~s|INSERT INTO "#{schema}".users (id) VALUES (gen_random_uuid()) RETURNING role|,
                 []
               )

      assert :ok =
               Ecto.Migrator.down(Repo, 20_261_111_130_110, AddUserRole,
                 prefix: schema,
                 log: false
               )

      assert %{rows: [[false, false]]} =
               SQL.query!(
                 Repo,
                 """
                 SELECT to_regclass($1) IS NOT NULL,
                        EXISTS (SELECT 1 FROM information_schema.columns
                                WHERE table_schema = $2 AND table_name = 'users'
                                  AND column_name = 'role')
                 """,
                 ["#{schema}.audit_events", schema]
               )

      assert :ok =
               Ecto.Migrator.up(Repo, 20_261_111_130_110, AddUserRole,
                 prefix: schema,
                 log: false
               )

      assert %{rows: [[true, "user"]]} =
               SQL.query!(
                 Repo,
                 ~s|SELECT to_regclass($1) IS NOT NULL, role FROM "#{schema}".users|,
                 ["#{schema}.audit_events"]
               )
    after
      Sandbox.mode(Repo, :manual)
    end
  end
end
