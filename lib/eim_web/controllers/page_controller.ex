defmodule EimWeb.PageController do
  use EimWeb, :controller

  def home(conn, _params) do
    render(conn, :home, current_user: conn.assigns[:current_user])
  end
end
