defmodule Eim.Repo.Migrations.CreateExtensionAuthCodes do
  use Ecto.Migration

  def change do
    create table(:extension_auth_codes, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :code_hash, :binary, null: false
      add :code_challenge, :string, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :consumed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:extension_auth_codes, [:code_hash])
    create index(:extension_auth_codes, [:expires_at])
  end
end
