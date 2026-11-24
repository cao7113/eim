defmodule EimWeb.ExtensionAuthController do
  use EimWeb, :controller
  require Ash.Query
  require Logger

  alias Eim.Accounts
  alias Eim.Accounts.User

  @api_key_lifetime_days 7

  def authx(conn, params) do
    Logger.info("Authx extension authorization request started")

    with {:ok, request} <- build_authx_request(params),
         :ok <- validate_extension_redirect_uri(request.redirect_uri) do
      case exchange_and_register(request) do
        {:ok, credentials} ->
          Logger.info("Authx extension authorization completed")
          json(conn, credentials)

        {:error, :invalid_code} ->
          Logger.info("Authx extension authorization rejected: invalid or expired code")
          send_resp(conn, :unauthorized, "Invalid or expired authorization code")

        {:error, :email_not_verified} ->
          Logger.info("Authx extension authorization rejected: email is not verified")
          send_resp(conn, :unauthorized, "Authx account email is not verified")

        {:error, reason} ->
          Logger.error(
            "Authx extension authorization failed after token exchange: #{inspect(reason)}"
          )

          internal_error(conn, "connect extension", reason)
      end
    else
      {:error, :invalid_redirect_uri} ->
        Logger.info(
          "Authx extension authorization request rejected while validating redirect URI"
        )

        send_resp(conn, :bad_request, "Invalid extension authorization request")

      {:error, :invalid_request} ->
        Logger.info("Authx extension authorization request rejected during request validation")

        send_resp(conn, :bad_request, "Invalid extension authorization request")
    end
  end

  def me(conn, _params) do
    case conn.assigns[:current_user] do
      %{id: id, email: email} -> json(conn, %{id: id, email: email})
      _ -> send_resp(conn, :unauthorized, "Authentication required")
    end
  end

  def revoke(conn, %{"key_id" => key_id}) do
    case {conn.assigns[:current_user], Ecto.UUID.cast(key_id)} do
      {%{id: user_id}, {:ok, key_id}} ->
        query = Ash.Query.filter(Accounts.ApiKey, id == ^key_id and user_id == ^user_id)

        case Ash.read_one(query, domain: Accounts, authorize?: false) do
          {:ok, nil} ->
            send_resp(conn, :no_content, "")

          {:ok, api_key} ->
            case Ash.destroy(api_key, authorize?: false) do
              :ok -> send_resp(conn, :no_content, "")
              {:error, reason} -> internal_error(conn, "revoke API key", reason)
            end

          {:error, reason} ->
            internal_error(conn, "read API key", reason)
        end

      _ ->
        send_resp(conn, :unauthorized, "Authentication required")
    end
  end

  def revoke(conn, _params), do: send_resp(conn, :bad_request, "Missing API key id")

  defp build_authx_request(%{
         "code" => code,
         "state" => state,
         "nonce" => nonce,
         "code_verifier" => verifier,
         "redirect_uri" => redirect_uri
       })
       when is_binary(code) and byte_size(code) in 1..2048 and
              is_binary(state) and byte_size(state) in 16..256 and
              is_binary(nonce) and byte_size(nonce) in 16..256 and
              is_binary(verifier) and byte_size(verifier) in 43..128 and
              is_binary(redirect_uri) and byte_size(redirect_uri) in 1..2048 do
    {:ok,
     %{
       code: code,
       state: state,
       nonce: nonce,
       verifier: verifier,
       redirect_uri: redirect_uri
     }}
  end

  defp build_authx_request(_params) do
    Logger.info("Authx extension authorization rejected: request fields failed validation")
    {:error, :invalid_request}
  end

  defp validate_extension_redirect_uri(redirect_uri) do
    allowed = Application.fetch_env!(:eim, :extension_oidc_redirect_uris)

    if redirect_uri in allowed do
      :ok
    else
      Logger.info("Authx extension authorization rejected: redirect URI is not allowlisted")
      {:error, :invalid_redirect_uri}
    end
  end

  defp exchange_and_register(request) do
    case oidc_client().exchange(
           request.code,
           request.state,
           request.nonce,
           request.verifier,
           request.redirect_uri
         ) do
      {:ok, user_info, oauth_tokens} ->
        with :ok <- validate_user_info(user_info),
             {:ok, user} <- register_user(user_info, oauth_tokens),
             {:ok, credentials} <- create_api_key(user) do
          {:ok, credentials}
        else
          {:error, :email_not_verified} = error ->
            error

          {:error, reason} = error ->
            Logger.error(
              "Authx extension user registration or API key creation failed: #{inspect(reason)}"
            )

            error
        end

      {:error, :invalid_code} = error ->
        error

      {:error, reason} ->
        Logger.error("Authx extension OIDC exchange failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp validate_user_info(user_info) do
    if user_info["email_verified"] == true and is_binary(user_info["sub"]) and
         is_binary(user_info["email"]) do
      :ok
    else
      Logger.info("Authx extension user info rejected: missing subject/email or unverified email")
      {:error, :email_not_verified}
    end
  end

  defp register_user(user_info, oauth_tokens) do
    User
    |> Ash.Changeset.for_create(
      :register_with_authx,
      %{user_info: user_info, oauth_tokens: oauth_tokens},
      authorize?: false
    )
    |> Ash.create(domain: Accounts, authorize?: false)
  end

  defp oidc_client do
    Application.get_env(:eim, :extension_oidc_client, Eim.Accounts.ExtensionOidc)
  end

  defp create_api_key(user) do
    expires_at =
      DateTime.utc_now()
      |> DateTime.add(@api_key_lifetime_days * 24 * 60 * 60, :second)
      |> DateTime.truncate(:microsecond)

    case Ash.create(
           Accounts.ApiKey,
           %{user_id: user.id, expires_at: expires_at},
           domain: Accounts,
           authorize?: false
         ) do
      {:ok, api_key} ->
        token = Ash.Resource.get_metadata(api_key, :plaintext_api_key)

        if is_binary(token) do
          {:ok,
           %{
             token: token,
             key_id: api_key.id,
             expires_at: expires_at,
             user: %{id: user.id, email: to_string(user.email)}
           }}
        else
          {:error, :api_key_not_generated}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp internal_error(conn, action, reason) do
    Logger.error("Unable to #{action}: #{inspect(reason)}")
    send_resp(conn, :internal_server_error, "Request failed")
  end
end
