defmodule EimWeb.EcdictSessionController do
  use EimWeb, :controller

  def sign_in(conn, %{"id" => id}) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        query = if conn.query_string == "", do: "", else: "?" <> conn.query_string

        conn
        |> put_session(:return_to, "/dicts/ecdict/#{id}" <> query)
        |> redirect(to: ~p"/sign-in")

      :error ->
        conn
        |> put_flash(:error, "This dictionary entry could not be found.")
        |> redirect(to: ~p"/dicts/ecdict")
    end
  end
end
