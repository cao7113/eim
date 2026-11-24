defmodule EimWeb.Auth.LiveAdminAuth do
  @moduledoc """
  LiveView `on_mount` hooks that restrict the management dashboards to current
  administrators.

  Access is re-checked against the database on mount and on every event and
  navigation, so an already open page cannot keep operating on stale access.
  """

  import Phoenix.LiveView

  alias Eim.Admins

  def on_mount(:ash_admin, _params, _session, socket) do
    authorize(socket.assigns[:current_user], socket)
  end

  def on_mount(:oban, _params, session, socket) do
    authorize(session["user"], socket)
  end

  defp authorize(%{id: id}, socket) do
    if Admins.admin?(id) do
      {:cont,
       socket
       |> attach_hook(:admin_access_event, :handle_event, fn _event, _params, socket ->
         if Admins.admin?(id), do: {:cont, socket}, else: {:halt, redirect(socket, to: "/")}
       end)
       |> attach_hook(:admin_access_params, :handle_params, fn _params, _uri, socket ->
         if Admins.admin?(id), do: {:cont, socket}, else: {:halt, redirect(socket, to: "/")}
       end)}
    else
      {:halt, redirect(socket, to: "/")}
    end
  end

  defp authorize(_, socket), do: {:halt, redirect(socket, to: "/")}
end
