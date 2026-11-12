defmodule Eim.Accounts.Changes.ChangeAdminRole do
  use Ash.Resource.Change

  require Ash.Query

  alias Eim.Accounts.{Admins, User}
  alias Eim.Audit.Event
  alias Eim.Repo

  @lock_key 2_134_429_344

  @impl true
  def change(changeset, opts, context) do
    bootstrap? = Keyword.get(opts, :bootstrap?, false)
    actor_id = if context.actor, do: context.actor.id

    changeset
    |> Ash.Changeset.before_action(fn changeset ->
      Ecto.Adapters.SQL.query!(Repo, "SELECT pg_advisory_xact_lock($1)", [@lock_key])
      current = Ash.get!(User, changeset.data.id, domain: Eim.Accounts, authorize?: false)
      changeset = %{changeset | data: current}
      role = if bootstrap?, do: :admin, else: Ash.Changeset.get_argument(changeset, :role)

      cond do
        bootstrap? and admins_exist?() ->
          Ash.Changeset.add_error(changeset, field: :role, message: "already_bootstrapped")

        not bootstrap? and not Admins.admin?(actor_id) ->
          Ash.Changeset.add_error(changeset, field: :role, message: "forbidden")

        current.role == :admin and role == :user and admin_count() == 1 ->
          Ash.Changeset.add_error(changeset, field: :role, message: "last_admin")

        true ->
          Ash.Changeset.force_change_attribute(changeset, :role, role)
      end
    end)
    |> Ash.Changeset.after_action(fn changeset, user ->
      if changeset.data.role == user.role do
        {:ok, user}
      else
        attrs = %{
          event_type: if(user.role == :admin, do: "admin.granted", else: "admin.revoked"),
          actor_id: actor_id,
          subject_type: "user",
          subject_id: user.id,
          details: %{
            old_role: changeset.data.role,
            new_role: user.role,
            method: if(bootstrap?, do: :bootstrap, else: :admin)
          }
        }

        case Event
             |> Ash.Changeset.for_create(:record, attrs)
             |> Ash.create(domain: Eim.Audit, authorize?: false) do
          {:ok, _record} -> {:ok, user}
          {:error, error} -> {:error, error}
        end
      end
    end)
    |> Ash.Changeset.after_transaction(fn _changeset, result ->
      case result do
        {:ok, %{role: :user, id: id}} ->
          :ok =
            Phoenix.PubSub.broadcast(
              Eim.PubSub,
              Admins.access_topic(id),
              :admin_access_revoked
            )

        _ ->
          :ok
      end

      result
    end)
  end

  defp admins_query, do: Ash.Query.filter(User, role == :admin)
  defp admins_exist?, do: Ash.exists?(admins_query(), domain: Eim.Accounts, authorize?: false)
  defp admin_count, do: Ash.count!(admins_query(), domain: Eim.Accounts, authorize?: false)
end
