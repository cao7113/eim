defmodule Eim.Dict.LexemeForm do
  use Ash.Resource,
    otp_app: :eim,
    domain: Eim.Dict,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "lexeme_forms"
    repo Eim.Repo

    references do
      reference :lexeme, on_delete: :delete
    end

    custom_indexes do
      index [:form_lc]
    end
  end

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id
    attribute :form, :string, allow_nil?: false, public?: true
    attribute :form_lc, :string, allow_nil?: false
    attribute :form_type, :string, allow_nil?: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :lexeme, Eim.Dict.Lexeme, allow_nil?: false
  end

  identities do
    identity :unique_form, [:lexeme_id, :form_lc, :form_type]
  end
end
