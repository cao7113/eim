defmodule Eim.Accounts.ExtensionOidc do
  @moduledoc """
  Exchanges a browser-extension authorization code with Authx.

  The extension performs the authorization request itself (public client +
  PKCE). This module runs on the server so that the token exchange and ID Token
  verification do not depend on the extension implementing JWT validation.
  """

  @doc """
  Exchanges `code` for Authx tokens and returns the verified user claims.

  `state`, `nonce` and `verifier` come from the extension's authorization
  request and are checked by Assent against the provider response.
  """
  def exchange(code, state, nonce, verifier, redirect_uri)
      when is_binary(code) and is_binary(state) and is_binary(nonce) and
             is_binary(verifier) and is_binary(redirect_uri) do
    config = [
      client_id: Application.fetch_env!(:eim, :extension_oidc_client_id),
      base_url: Application.fetch_env!(:eim, :oidc_issuer),
      redirect_uri: redirect_uri,
      client_authentication_method: "none",
      code_verifier: true,
      session_params: %{state: state, nonce: nonce, code_verifier: verifier},
      http_adapter:
        Application.get_env(
          :ash_authentication,
          :http_adapter,
          {Assent.HTTPAdapter.Finch, supervisor: AshAuthentication.Finch}
        )
    ]

    case Assent.Strategy.OIDC.callback(config, %{"code" => code, "state" => state}) do
      {:ok, %{user: user_info, token: oauth_tokens}} ->
        {:ok, user_info, oauth_tokens}

      {:error, reason} ->
        require Logger
        Logger.warning("Authx extension token exchange failed: #{inspect(reason)}")
        {:error, :invalid_code}
    end
  end
end
