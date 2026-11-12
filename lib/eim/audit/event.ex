defmodule Eim.Audit.Event do
  use Ash.Resource,
    otp_app: :eim,
    domain: Eim.Audit,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAdmin.Resource]

  admin do
    create_actions []
    table_columns [:inserted_at, :event_type, :actor_id, :subject_type, :subject_id, :details]
    table_sortable_columns [:inserted_at, :event_type, :actor_id, :subject_type, :subject_id]
    table_filterable_columns [:event_type, :actor_id, :subject_type, :subject_id]
  end

  postgres do
    table "audit_events"
    repo Eim.Repo
  end

  actions do
    defaults [:read]

    create :record do
      accept [:event_type, :actor_id, :subject_type, :subject_id, :details]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if Eim.Accounts.Checks.AdminCheck
    end

    policy action(:record) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :event_type, :string, allow_nil?: false, public?: true
    attribute :actor_id, :uuid, public?: true
    attribute :subject_type, :string, allow_nil?: false, public?: true
    attribute :subject_id, :uuid, allow_nil?: false, public?: true
    attribute :details, :map, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
  end
end
