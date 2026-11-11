defmodule EimWeb.ExtensionAuthController do
  use EimWeb, :controller
  require Ash.Query

  alias Eim.Accounts
  alias Eim.Accounts.ExtensionAuth
  alias Eim.Repo

  @api_key_lifetime_days 30

  def authorize(conn, params) do
    with {:ok, redirect_uri} <- validate_redirect_uri(params["redirect_uri"]),
         {:ok, challenge} <- validate_challenge(params["code_challenge"]),
         {:ok, state} <- validate_state(params["state"]) do
      case conn.assigns[:current_user] do
        nil ->
          return_to =
            "/extension/authorize?" <>
              URI.encode_query(%{
                "redirect_uri" => redirect_uri,
                "code_challenge" => challenge,
                "state" => state
              })

          conn
          |> put_session(:return_to, return_to)
          |> redirect(to: ~p"/sign-in")

        user ->
          case ExtensionAuth.issue_code(user.id, challenge) do
            {:ok, code} ->
              callback_uri =
                redirect_uri <>
                  "#" <>
                  URI.encode_query(%{"code" => code, "state" => state})

              redirect(conn, external: callback_uri)

            {:error, reason} ->
              require Logger
              Logger.error("Unable to issue extension authorization code: #{inspect(reason)}")
              send_resp(conn, :internal_server_error, "Unable to start extension authorization")
          end
      end
    else
      {:error, _reason} ->
        send_resp(conn, :bad_request, "Invalid extension authorization request")
    end
  end

  def exchange(conn, %{"code" => code, "code_verifier" => verifier}) do
    result =
      Repo.transaction(fn ->
        with {:ok, user_id} <- ExtensionAuth.consume_code(code, verifier),
             {:ok, user} <- get_user(user_id),
             {:ok, credentials} <- create_api_key(user) do
          credentials
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, credentials} ->
        json(conn, credentials)

      {:error, :invalid_code} ->
        send_resp(conn, :unauthorized, "Invalid or expired authorization code")

      {:error, reason} ->
        require Logger
        Logger.error("Unable to exchange extension authorization code: #{inspect(reason)}")
        send_resp(conn, :internal_server_error, "Unable to connect extension")
    end
  end

  def exchange(conn, _params) do
    send_resp(conn, :bad_request, "Missing authorization code or verifier")
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

  defp get_user(user_id) do
    case Ash.get(Accounts.User, user_id,
           domain: Accounts,
           authorize?: false
         ) do
      {:ok, nil} -> {:error, :user_not_found}
      result -> result
    end
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

  defp validate_redirect_uri(uri) when is_binary(uri) do
    case URI.parse(uri) do
      %URI{scheme: "https", host: host, path: "/", port: 443, query: nil, fragment: nil} ->
        if Regex.match?(~r/\A[a-p]{32}\.chromiumapp\.org\z/, host) do
          {:ok, uri}
        else
          {:error, :invalid_redirect_uri}
        end

      _ ->
        {:error, :invalid_redirect_uri}
    end
  end

  defp validate_redirect_uri(_), do: {:error, :invalid_redirect_uri}

  defp validate_challenge(challenge) when is_binary(challenge) do
    if Regex.match?(~r/\A[A-Za-z0-9_-]{43}\z/, challenge),
      do: {:ok, challenge},
      else: {:error, :invalid_challenge}
  end

  defp validate_challenge(_), do: {:error, :invalid_challenge}

  defp validate_state(state) when is_binary(state) do
    if Regex.match?(~r/\A[A-Za-z0-9_-]{32,128}\z/, state),
      do: {:ok, state},
      else: {:error, :invalid_state}
  end

  defp validate_state(_), do: {:error, :invalid_state}

  defp internal_error(conn, action, reason) do
    require Logger
    Logger.error("Unable to #{action}: #{inspect(reason)}")
    send_resp(conn, :internal_server_error, "Request failed")
  end
end
