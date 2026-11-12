defmodule EimWeb.AdminDashboardAuth do
  import Phoenix.LiveView

  alias Eim.Accounts.Admins

  def on_mount(:ash_admin, _params, _session, socket) do
    authorize(socket.assigns[:current_user], socket)
  end

  def on_mount(:oban, _params, session, socket) do
    authorize(session["user"], socket)
  end

  defp authorize(%{id: id}, socket) do
    if connected?(socket), do: :ok = Phoenix.PubSub.subscribe(Eim.PubSub, Admins.access_topic(id))

    if Admins.admin?(id) do
      {:cont,
       socket
       |> attach_hook(:admin_access_changed, :handle_info, fn
         :admin_access_revoked, socket -> {:halt, redirect(socket, to: "/")}
         _, socket -> {:cont, socket}
       end)
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
