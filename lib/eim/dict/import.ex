defmodule Eim.Dict.Import do
  use Ash.Resource,
    otp_app: :eim,
    domain: Eim.Dict,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "dictionary_imports"
    repo Eim.Repo
  end

  actions do
    defaults [:read]

    create :record do
      accept [:source, :source_version, :file_sha256, :row_count, :notes]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :source, :string, allow_nil?: false, public?: true
    attribute :source_version, :string, allow_nil?: false, public?: true
    attribute :file_sha256, :string, allow_nil?: false, public?: true
    attribute :row_count, :integer, allow_nil?: false, public?: true
    attribute :notes, :string, public?: true
    timestamps()
  end
end
