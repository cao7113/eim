defmodule Eim.Secrets do
  use AshAuthentication.Secret

  def secret_for([:authentication, :tokens, :signing_secret], Eim.Accounts.User, _opts, _context) do
    Application.fetch_env(:eim, :token_signing_secret)
  end
end
