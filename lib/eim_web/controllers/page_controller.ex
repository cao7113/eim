defmodule EimWeb.PageController do
  use EimWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
