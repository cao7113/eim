defmodule Eim.Dict.Import do
  use Ash.Resource,
    otp_app: :eim,
    domain: Eim.Dict,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    name "Imports"
    table_columns [:source_path, :row_count, :duration_ms, :updated_at]
    table_sortable_columns [:source_path, :source_sha256, :row_count, :duration_ms, :updated_at]
    table_filterable_columns [:source_path, :source_sha256, :updated_at]
  end

  postgres do
    table "dictionary_imports"
    repo Eim.Repo
  end

  actions do
    defaults [:read]

    create :record do
      accept [:source_path, :source_sha256, :row_count, :duration_ms, :notes]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :source_path, :string, allow_nil?: false, public?: true
    attribute :source_sha256, :string, public?: true
    attribute :row_count, :integer, allow_nil?: false, public?: true
    attribute :duration_ms, :integer, public?: true, constraints: [min: 0]
    attribute :notes, :string, public?: true
    timestamps()
  end
end
