defmodule EimWeb.ObanResolver do
  @behaviour Oban.Web.Resolver

  @impl true
  def resolve_user(%{assigns: %{current_user: %Eim.Accounts.User{id: id}}}), do: %{id: id}
  def resolve_user(_conn), do: nil

  @impl true
  def resolve_access(%{id: id}) do
    if Eim.Accounts.Admins.admin?(id), do: :all, else: {:forbidden, "/"}
  end

  def resolve_access(_), do: {:forbidden, "/"}
end
