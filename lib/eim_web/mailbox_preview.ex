defmodule EimWeb.MailboxPreview do
  @moduledoc false

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    if Application.get_env(:swoosh, :local, false) do
      Plug.Swoosh.MailboxPreview.call(conn, opts)
    else
      conn
      |> Plug.Conn.send_resp(:not_found, "Not Found")
      |> Plug.Conn.halt()
    end
  end
end
