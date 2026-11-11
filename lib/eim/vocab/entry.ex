defmodule Eim.Vocab.Entry do
  use Ash.Resource,
    otp_app: :eim,
    domain: Eim.Vocab,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  postgres do
    table "vocab_entries"
    repo Eim.Repo
  end

  json_api do
    type "vocab-entry"

    routes do
      base "/vocab/entries"

      index :read
      post :create
      patch :update_note
      delete :destroy
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:lookup_text, :lemma, :phonetic, :dictionary_snapshot, :note]
      upsert? true
      upsert_identity :unique_owner_term
      upsert_fields []
      return_skipped_upsert? true

      change relate_actor(:user)

      change fn changeset, _context ->
        lookup_text = Ash.Changeset.get_attribute(changeset, :lookup_text)
        lemma = Ash.Changeset.get_attribute(changeset, :lemma)
        term = if is_binary(lemma) and String.trim(lemma) != "", do: lemma, else: lookup_text

        normalized_term =
          term
          |> String.normalize(:nfkc)
          |> String.trim()
          |> String.downcase()

        if normalized_term == "" do
          Ash.Changeset.add_error(changeset,
            field: :lookup_text,
            message: "must not be blank"
          )
        else
          Ash.Changeset.change_attribute(changeset, :term_key, normalized_term)
        end
      end
    end

    update :update_note do
      accept [:note]
    end

    destroy :destroy
  end

  policies do
    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
    end

    policy action_type(:update) do
      authorize_if relates_to_actor_via(:user)
    end

    policy action_type(:destroy) do
      authorize_if relates_to_actor_via(:user)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :term_key, :string do
      allow_nil? false
      public? true
    end

    attribute :lookup_text, :string do
      allow_nil? false
      public? true
      constraints max_length: 500
    end

    attribute :lemma, :string do
      public? true
      constraints max_length: 500
    end

    attribute :phonetic, :string, public?: true

    attribute :dictionary_snapshot, :map do
      allow_nil? false
      public? true
    end

    attribute :note, :string do
      public? true
      constraints max_length: 2000
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Eim.Accounts.User do
      allow_nil? false
    end
  end

  identities do
    identity :unique_owner_term, [:user_id, :term_key]
  end
end
