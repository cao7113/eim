defmodule Eim.Admins do
  @moduledoc """
  Administrator access operations.

  Access is stored in `Eim.Admins.Admin`, not in a role column on
  `Eim.Accounts.User`, so no registration or upsert path can grant it. Normal
  grants run through Ash policies and require an administrator actor.

  `bootstrap_admin/1` is the only path without an actor and runs with
  `authorize?: false`. It is reserved for trusted operational access: see
  `Eim.Ops`, which is the documented entry point for IEx sessions and mix
  tasks.
  """

  require Ash.Query

  alias Eim.Accounts
  alias Eim.Accounts.User
  alias Eim.Admins.Admin
  alias Eim.Admins.Domain

  @typedoc "A user struct, a user id or an email address."
  @type user_ref :: User.t() | String.t()

  @doc "Lists administrator records. Operational use only."
  def list(_filters \\ %{}) do
    Ash.read(Admin, domain: Domain, authorize?: false)
  end

  @doc """
  Fetches the administrator record of the user identified by `user_ref`.

  Returns `{:error, :not_admin}` when the user exists but is not an
  administrator, and `{:error, :not_found_user}` when no user matches.
  """
  def fetch_admin_by_user_ref(user_ref, opts \\ []) do
    with {:ok, %User{id: user_id} = user} <- Accounts.fetch_user_by_ref(user_ref) do
      # `authorize?: false` is required: authorizing this read would run
      # AdminCheck, which calls admin?/2, which reads this same resource.
      opts = Keyword.merge([domain: Domain, actor: user, authorize?: false], opts)

      Admin
      |> Ash.Query.filter(user_id == ^user_id)
      |> Ash.read_one(opts)
      |> case do
        # `read_one/2` answers `{:ok, nil}` when the user has no admin record,
        # which must not be passed through as `{:ok, nil}`: every caller below
        # (starting with fetch_admin_user_by_ref/2 and master/0) treats `{:ok, _}`
        # as "this user is an administrator".
        {:ok, %Admin{} = admin} -> {:ok, admin}
        _ -> {:error, :not_admin}
      end
    else
      _ -> {:error, :not_found_user}
    end
  end

  @doc "Like `fetch_admin_by_user_ref/2`, but returns `nil` instead of an error tuple."
  def get_admin_by_user_ref(user_ref, opts \\ []) do
    case fetch_admin_by_user_ref(user_ref, opts) do
      {:ok, admin} -> admin
      _ -> nil
    end
  end

  @doc "The email configured as the master administrator, or `nil` when unset."
  def master_email, do: Application.get_env(:eim, :master_email)

  @doc "The user configured by `master_email/0` when it is an administrator, or `nil`."
  def master, do: get_admin_user(master_email())

  @doc "Fetches the user identified by `user_ref` when that user is an administrator."
  def fetch_admin_user_by_ref(user_ref, opts \\ []) do
    case fetch_admin_by_user_ref(user_ref, opts) do
      {:ok, _admin} -> Accounts.fetch_user_by_ref(user_ref)
      other -> other
    end
  end

  @doc "Like `fetch_admin_user_by_ref/2`, but returns `nil` instead of an error tuple."
  def get_admin_user(user_ref, opts \\ []) do
    case fetch_admin_user_by_ref(user_ref, opts) do
      {:ok, user} -> user
      _ -> nil
    end
  end

  @doc """
  Whether `user_ref` identifies a current administrator.

  Never raises: unknown users, malformed references and read errors all return
  `false`.
  """
  def admin?(user_ref, opts \\ []) do
    not is_nil(get_admin_by_user_ref(user_ref, opts))
  end

  @doc "Grants administrator access to `user`, performed by `actor`."
  def grant_admin(%User{} = user, %User{} = actor) do
    grant_record(user, actor, authorize?: true)
  end

  @doc """
  Grants administrator access during a bootstrap flow, without an actor.

  Runs with `authorize?: false`, so it must only be called from trusted
  operational access (IEx, `Eim.Ops`, mix tasks), never from the web.
  """
  def bootstrap_admin(%User{} = user) do
    grant_record(user, nil, authorize?: false)
  end

  defp grant_record(%User{id: user_id} = user, actor, opts) do
    case get_admin_by_user_ref(user) do
      %Admin{} = admin ->
        {:ok, admin}

      nil ->
        Admin
        |> Ash.Changeset.for_create(:grant, %{user_id: user_id}, actor: actor)
        |> Ash.create(Keyword.merge([domain: Domain, actor: actor], opts))
    end
  end
end
