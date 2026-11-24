defmodule Eim.Accounts.User do
  use Ash.Resource,
    otp_app: :eim,
    domain: Eim.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication, AshAdmin.Resource]

  admin do
    table_columns [:email]
    actor? true
  end

  authentication do
    tokens do
      enabled? true
      token_resource Eim.Accounts.Token
      signing_secret Eim.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      oidc :authx do
        client_id Eim.Secrets
        base_url Eim.Secrets
        redirect_uri Eim.Secrets
        identity_resource Eim.Accounts.UserIdentity

        client_authentication_method "none"
        code_verifier true
        nonce true
        trust_email_verified? true
        authorization_params scope: "email"
      end

      api_key :api_key do
        api_key_relationship :valid_api_keys
        api_key_hash_attribute :api_key_hash
      end
    end
  end

  postgres do
    table "users"
    repo Eim.Repo
  end

  actions do
    defaults [:read]

    read :get_by_subject do
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    read :get_by_email do
      description "Looks up a user by their email"
      get_by :email
    end

    create :register_with_authx do
      description "Register or link a user from an Authx OIDC login."

      argument :user_info, :map, allow_nil?: false
      argument :oauth_tokens, :map, allow_nil?: false, sensitive?: true

      upsert? true
      upsert_identity :unique_email
      upsert_fields [:email]

      change AshAuthentication.GenerateTokenChange
      change Eim.Accounts.Changes.SetEmailFromUserInfo
      change AshAuthentication.Strategy.OAuth2.IdentityChange
    end

    read :sign_in_with_api_key do
      argument :api_key, :string, allow_nil?: false
      prepare AshAuthentication.Strategy.ApiKey.SignInPreparation
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end
  end

  relationships do
    has_many :valid_api_keys, Eim.Accounts.ApiKey do
      filter expr(valid)
    end
  end

  identities do
    identity :unique_email, [:email]
  end
end
