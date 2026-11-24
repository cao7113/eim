Code.require_file("../../priv/repo/migrations/20261124120000_add_admins.exs", __DIR__)

defmodule Eim.AdminsMigrationTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox
  alias Eim.Repo
  alias Eim.Repo.Migrations.AddAdmins

  @version 20_261_124_120_000

  test "backfills administrators and drops users.role" do
    schema = "admins_test_" <> String.replace(Ecto.UUID.generate(), "-", "")

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        SQL.query!(Repo, ~s(DROP SCHEMA IF EXISTS "#{schema}" CASCADE), [])
      end)
    end)

    Sandbox.mode(Repo, :auto)

    try do
      SQL.query!(Repo, ~s(CREATE SCHEMA "#{schema}"), [])

      # The migration qualifies its own raw SQL, but resolve unqualified names
      # to the schema as well so the test does not depend on how the migration
      # prefix is read.
      SQL.query!(Repo, ~s|SET search_path TO "#{schema}", public|, [])

      SQL.query!(
        Repo,
        ~s|CREATE TABLE "#{schema}".users (id uuid PRIMARY KEY, role text NOT NULL DEFAULT 'user')|,
        []
      )

      SQL.query!(
        Repo,
        ~s|ALTER TABLE "#{schema}".users ADD CONSTRAINT users_role_valid CHECK (role IN ('user','admin'))|,
        []
      )

      SQL.query!(
        Repo,
        ~s|INSERT INTO "#{schema}".users (id, role) VALUES (gen_random_uuid(), 'admin'), (gen_random_uuid(), 'user')|,
        []
      )

      assert :ok = Ecto.Migrator.up(Repo, @version, AddAdmins, prefix: schema, log: false)

      assert %{rows: [[true, 1]]} =
               SQL.query!(
                 Repo,
                 "SELECT to_regclass($1) IS NOT NULL, count(*) FROM #{schema}.admins",
                 ["#{schema}.admins"]
               )

      assert %{rows: [[nil]]} =
               SQL.query!(Repo, "SELECT granted_by_user_id FROM #{schema}.admins", [])

      refute has_role_column?(schema)

      assert :ok = Ecto.Migrator.down(Repo, @version, AddAdmins, prefix: schema, log: false)

      assert %{rows: [["admin"], ["user"]]} =
               SQL.query!(Repo, ~s|SELECT role FROM "#{schema}".users ORDER BY role|, [])

      assert %{rows: [[false]]} =
               SQL.query!(Repo, "SELECT to_regclass($1) IS NOT NULL", ["#{schema}.admins"])
    after
      SQL.query!(Repo, "SET search_path TO public", [])
      Sandbox.mode(Repo, :manual)
    end
  end

  defp has_role_column?(schema) do
    %{rows: [[exists?]]} =
      SQL.query!(
        Repo,
        """
        SELECT EXISTS (
          SELECT 1 FROM information_schema.columns
          WHERE table_schema = $1 AND table_name = 'users' AND column_name = 'role'
        )
        """,
        [schema]
      )

    exists?
  end
end
