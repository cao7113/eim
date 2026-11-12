defmodule Eim.Accounts.Admins do
  @moduledoc """
  Administrator role operations. Bootstrap is restricted to trusted IEx access.
  """

  require Ash.Query

  alias Eim.Accounts.User

  def access_topic(id), do: "admin-access:#{id}"

  def admin?(id) do
    case admin_status(id) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  def admin_status(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        User
        |> Ash.Query.filter(id == ^id and role == :admin)
        |> Ash.exists(domain: Eim.Accounts, authorize?: false)

      :error ->
        {:ok, false}
    end
  end

  def bootstrap(email) when is_binary(email) do
    case User
         |> Ash.Query.filter(role == :admin)
         |> Ash.exists(domain: Eim.Accounts, authorize?: false) do
      {:ok, true} -> {:error, :already_bootstrapped}
      {:ok, false} -> bootstrap_user(email)
      {:error, error} -> {:error, error}
    end
  end

  def bootstrap(_), do: {:error, :invalid_email}

  defp bootstrap_user(email) do
    case read_by_email(email, :get_by_email, authorize?: false) do
      {:ok, nil} -> {:error, :user_not_found}
      {:ok, user} -> update_role(user, :bootstrap_admin, %{}, authorize?: false)
      {:error, error} -> {:error, error}
    end
  end

  def find_by_email(actor, email) when is_binary(email) do
    read_by_email(email, :get_by_email_as_admin,
      actor: actor,
      authorize?: true,
      authorize_with: :error
    )
  end

  def set_role(actor_id, user_id, role) when role in [:user, :admin] do
    with {:ok, actor_id} <- Ecto.UUID.cast(actor_id),
         {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, true} <- admin_status(actor_id),
         {:ok, actor} <- get_user(actor_id),
         {:ok, user} <- get_user(user_id) do
      update_role(user, :set_admin_role, %{role: role}, actor: actor, authorize?: true)
    else
      :error -> {:error, :invalid_user_id}
      {:ok, false} -> {:error, :forbidden}
      {:error, error} -> {:error, error}
    end
  end

  def set_role(_, _, _), do: {:error, :invalid_role}

  defp read_by_email(email, action, opts) do
    User
    |> Ash.Query.for_read(action, %{email: String.trim(email)})
    |> Ash.read_one(Keyword.put(opts, :domain, Eim.Accounts))
  end

  defp get_user(id) do
    case Ash.get(User, id, domain: Eim.Accounts, authorize?: false) do
      {:ok, nil} -> {:error, :user_not_found}
      result -> result
    end
  end

  defp update_role(user, action, params, opts) do
    case user
         |> Ash.Changeset.for_update(action, params, opts)
         |> Ash.update(Keyword.put(opts, :domain, Eim.Accounts)) do
      {:error, %Ash.Error.Forbidden{}} ->
        {:error, :forbidden}

      {:error, %Ash.Error.Invalid{errors: errors} = error} ->
        case Enum.find(errors, &role_error/1) do
          %{message: "last_admin"} -> {:error, :last_admin}
          %{message: "already_bootstrapped"} -> {:error, :already_bootstrapped}
          %{message: "forbidden"} -> {:error, :forbidden}
          nil -> {:error, error}
        end

      result ->
        result
    end
  end

  defp role_error(%{field: :role, message: message})
       when message in ["last_admin", "already_bootstrapped", "forbidden"],
       do: true

  defp role_error(_), do: false
end
