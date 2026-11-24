defmodule Eim.Vocab.Entry do
  use Ash.Resource,
    otp_app: :eim,
    domain: Eim.Vocab,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource, AshAdmin.Resource]

  admin do
    table_columns [:term_key, :lemma, :updated_at]
  end

  postgres do
    table "vocab_entries"
    repo Eim.Repo
  end

  alias Eim.Vocab.Changes.SetTermKey

  json_api do
    type "vocab-entry"

    routes do
      base "/vocab/entries"

      index :read
      post :create
      patch :update_note
      delete :destroy
      route :post, "/import", :import
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
      change SetTermKey
    end

    update :update_note do
      accept [:note]
    end

    destroy :destroy

    action :import, :map do
      description "Look up and import multiple dictionary entries into the current user's vocabulary."

      # [
      #   {"word": "ephemeral", "note": "en"},
      #   {"word": "serendipity", "note": "en"}
      # ]
      # todo how to input in admin page
      argument :entries, {:array, :map} do
        allow_nil? false
        constraints max_length: 500

        # constraints items: [
        #               fields: [
        #                 word: [type: :string, allow_nil?: false],
        #                 note: [type: :string]
        #               ]
        #             ]
        # constraints items: [
        #               fields: [
        #                 word: [type: :string, allow_nil?: false],
        #                 note: [type: :string]
        #               ]
        #             ],
        #             max_length: 500
      end

      constraints fields: [
                    total: [type: :integer, allow_nil?: false],
                    matched: [type: :integer, allow_nil?: false],
                    created: [type: :integer, allow_nil?: false],
                    updated: [type: :integer, allow_nil?: false],
                    skipped: [type: :integer, allow_nil?: false],
                    results: [type: {:array, :map}]
                  ]

      run Eim.Vocab.Import
    end
  end

  policies do
    policy action(:import) do
      authorize_if actor_present()
    end

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

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Eim.Accounts.User do
      allow_nil? false
    end
  end

  identities do
    identity :unique_owner_term, [:user_id, :term_key]
  end

  def term_key_for(nil), do: ""

  def term_key_for(term) when is_binary(term) do
    term
    |> String.normalize(:nfkc)
    |> String.trim()
    |> String.downcase()
  end

  def term_key_for(_term), do: ""
end
