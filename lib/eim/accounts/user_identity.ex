defmodule Eim.Accounts.UserIdentity do
  use Ash.Resource,
    otp_app: :eim,
    domain: Eim.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.UserIdentity]

  user_identity do
    user_resource Eim.Accounts.User
  end

  postgres do
    table "user_identities"
    repo Eim.Repo
  end
end
