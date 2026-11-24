defmodule Eim.Admins.Admin do
  @moduledoc """
  Administrator access granted to a user.

  Access lives in its own table rather than in a `role` column on
  `Eim.Accounts.User`, so no user registration or upsert path can grant it:
  writes only happen through the `:grant` action, which requires an actor that
  is already an administrator.
  """

  use Ash.Resource,
    otp_app: :eim,
    domain: Eim.Admins.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAdmin.Resource]

  admin do
    label_field :user_email
    show_calculations [:user_email, :granted_by_email]
    table_columns [:id, :user_email, :granted_at, :granted_by_email]
  end

  postgres do
    table "admins"
    repo Eim.Repo
  end

  actions do
    defaults [:read]

    create :grant do
      description "Grants administrator access to an existing user. Administrators only."

      accept [:user_id]

      # The actor owns `granted_by_user_id`; it cannot be spoofed from a form.
      change Eim.Admins.Changes.SetGrantedBy
      change Eim.Admins.Changes.RecordAdminEvent
    end

    # No `:update` and no `:destroy` action on purpose: withdrawing access is
    # not implemented, and one write path keeps the audit trail complete.
  end

  policies do
    policy action(:read) do
      authorize_if Eim.Admins.Checks.AdminCheck
    end

    policy action(:grant) do
      authorize_if Eim.Admins.Checks.AdminCheck
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :granted_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      description "Timestamp when administrator access was granted."
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Eim.Accounts.User do
      allow_nil? false
      attribute_writable? true
      primary_key? false
    end

    belongs_to :granted_by, Eim.Accounts.User do
      source_attribute :granted_by_user_id
      allow_nil? true
      attribute_writable? true
      primary_key? false
      description "The administrator who granted access; empty for bootstrap."
    end
  end

  calculations do
    calculate :user_email, :ci_string, expr(user.email)
    calculate :granted_by_email, :ci_string, expr(granted_by.email)
  end

  identities do
    identity :unique_user, [:user_id]
  end
end
