defmodule Eim.Admins.Changes.SetGrantedBy do
  @moduledoc """
  Sets the administrator who granted access from the Ash actor.

  The actor is intentionally used instead of accepting `granted_by_user_id`
  from the client or from an AshAdmin form, so the audit field cannot be
  spoofed. Bootstrap has no actor, and leaves `granted_by_user_id` empty.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, %{actor: %{id: actor_id}}) when is_binary(actor_id) do
    Ash.Changeset.force_change_attribute(changeset, :granted_by_user_id, actor_id)
  end

  def change(changeset, _opts, _context), do: changeset
end
