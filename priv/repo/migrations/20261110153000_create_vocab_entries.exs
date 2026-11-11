defmodule Eim.Repo.Migrations.CreateVocabEntries do
  use Ecto.Migration

  def change do
    create table(:vocab_entries, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :term_key, :text, null: false
      add :lookup_text, :text, null: false
      add :lemma, :text
      add :phonetic, :text
      add :dictionary_snapshot, :map, null: false
      add :note, :text

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :user_id,
          references(:users,
            column: :id,
            name: "vocab_entries_user_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false
    end

    create unique_index(:vocab_entries, [:user_id, :term_key],
             name: "vocab_entries_unique_owner_term_index"
           )
  end
end
