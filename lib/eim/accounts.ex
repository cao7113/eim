defmodule Eim.Accounts do
  @moduledoc """
  Accounts domain and user lookup helpers.

  Users are local mirrors of Authx identities. Administrator access is not
  part of this resource: see `Eim.Admins`.
  """

  use Ash.Domain, otp_app: :eim, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Eim.Accounts.User
    resource Eim.Accounts.UserIdentity
    resource Eim.Accounts.ApiKey
    resource Eim.Accounts.Token
  end

  require Ash.Query
  alias Eim.Accounts.User

  @typedoc "A user struct, a user id or an email address."
  @type user_ref :: User.t() | String.t()

  @doc """
  Resolves `user_ref` to a user.

  Ids are looked up by primary key, anything else is treated as an email.
  Lookups bypass read authorization: policies guard mutations, and this helper
  only resolves existing records for operational callers.
  """
  def fetch_user_by_ref(user_ref, opts \\ [])
  def fetch_user_by_ref(%User{} = user, _opts), do: {:ok, user}

  def fetch_user_by_ref(user_ref, opts) when is_binary(user_ref) do
    opts = Keyword.merge([domain: __MODULE__, authorize?: false], opts)

    case Ecto.UUID.cast(user_ref) do
      {:ok, user_id} ->
        User
        |> Ash.Query.filter(id == ^user_id)
        |> Ash.read_one(opts)

      :error ->
        User
        |> Ash.Query.for_read(:get_by_email, %{email: String.trim(user_ref)})
        |> Ash.read_one(opts)
    end
  end

  def fetch_user_by_ref(_user_ref, _opts), do: {:ok, nil}
end
