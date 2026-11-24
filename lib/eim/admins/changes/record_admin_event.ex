defmodule Eim.Admins.Changes.RecordAdminEvent do
  @moduledoc """
  Records an `admin.granted` audit event in the same transaction as the grant.

  A failed audit write fails the grant: the event is the history of
  administrative access, so it must never be lost silently. `method` is derived
  from the actor — grants performed by an administrator are `:admin`, grants
  without an actor are `:bootstrap`.
  """

  use Ash.Resource.Change

  alias Eim.Audit.Event

  @impl true
  def change(changeset, _opts, %{actor: actor}) do
    method = if actor, do: :admin, else: :bootstrap

    Ash.Changeset.after_action(changeset, fn _changeset, admin ->
      attrs = %{
        event_type: "admin.granted",
        actor_id: actor && actor.id,
        subject_type: "user",
        subject_id: admin.user_id,
        details: %{old_role: :user, new_role: :admin, method: method}
      }

      case Event
           |> Ash.Changeset.for_create(:record, attrs)
           |> Ash.create(domain: Eim.Audit, authorize?: false) do
        {:ok, _event} -> {:ok, admin}
        {:error, error} -> {:error, error}
      end
    end)
  end
end
