defmodule Eim.Secrets do
  use AshAuthentication.Secret

  def secret_for([:authentication, :tokens, :signing_secret], Eim.Accounts.User, _opts, _context) do
    Application.fetch_env(:eim, :token_signing_secret)
  end

  def secret_for(
        [:authentication, :strategies, :authx, key],
        Eim.Accounts.User,
        _opts,
        _context
      )
      when key in [:client_id, :base_url, :redirect_uri] do
    config_key =
      case key do
        :client_id -> :oidc_client_id
        :base_url -> :oidc_issuer
        :redirect_uri -> :oidc_redirect_uri
      end

    Application.fetch_env(:eim, config_key)
  end
end
