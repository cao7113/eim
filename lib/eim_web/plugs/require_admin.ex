defmodule EimWeb.Plugs.RequireAdmin do
  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    user = conn.assigns[:current_user]

    if user && Eim.Accounts.Admins.admin?(user.id) do
      conn
    else
      conn |> redirect(to: "/") |> halt()
    end
  end
end
