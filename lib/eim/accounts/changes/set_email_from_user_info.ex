defmodule Eim.Accounts.Changes.SetEmailFromUserInfo do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    user_info = Ash.Changeset.get_argument(changeset, :user_info)

    Ash.Changeset.change_attribute(changeset, :email, user_info["email"])
  end
end
