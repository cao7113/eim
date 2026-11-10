defmodule Eim.Accounts do
  use Ash.Domain, otp_app: :eim, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Eim.Accounts.Token
    resource Eim.Accounts.User
    resource Eim.Accounts.ApiKey
  end
end
