defmodule EimWeb.Auth.RequireAdminPlug do
  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    user = conn.assigns[:current_user]

    if user && Eim.Admins.admin?(user) do
      conn
    else
      conn |> redirect(to: "/") |> halt()
    end
  end
end
