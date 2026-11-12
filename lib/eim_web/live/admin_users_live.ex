defmodule EimWeb.AdminUsersLive do
  use EimWeb, :live_view

  require Logger

  alias Eim.Accounts.Admins

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "User administration",
       form: to_form(%{"email" => ""}, as: :search),
       selected_user: nil
     )}
  end

  @impl true
  def handle_event("search", %{"search" => %{"email" => email}}, socket) do
    if Admins.admin?(socket.assigns.current_user.id) do
      email = String.trim(email)

      case Admins.find_by_email(socket.assigns.current_user, email) do
        {:ok, user} ->
          {:noreply,
           socket
           |> assign(form: to_form(%{"email" => email}, as: :search), selected_user: user)
           |> maybe_not_found(user)}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, redirect(socket, to: ~p"/")}

        {:error, error} ->
          Logger.error("Failed to search for user: #{inspect(error)}")
          {:noreply, put_flash(socket, :error, "Could not search for the user.")}
      end
    else
      {:noreply, redirect(socket, to: ~p"/")}
    end
  end

  def handle_event("set-role", %{"id" => id, "role" => role}, socket)
      when role in ["admin", "user"] do
    role = if role == "admin", do: :admin, else: :user

    case Admins.set_role(socket.assigns.current_user.id, id, role) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(selected_user: user)
         |> put_flash(:info, "User role updated.")}

      {:error, :forbidden} ->
        {:noreply, redirect(socket, to: ~p"/")}

      {:error, :last_admin} ->
        {:noreply, put_flash(socket, :error, "The last administrator cannot be removed.")}

      {:error, reason} ->
        Logger.error("Failed to change administrator role: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Could not update the user role.")}
    end
  end

  defp maybe_not_found(socket, nil), do: put_flash(socket, :error, "User not found.")
  defp maybe_not_found(socket, _user), do: socket

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <section class="mx-auto max-w-2xl space-y-6 py-8">
        <div>
          <h1 class="text-2xl font-semibold">User administration</h1>
          <p class="mt-2 text-sm text-slate-600">
            Find a registered user by email to manage their role.
          </p>
        </div>
        <.form for={@form} id="admin-user-search" phx-submit="search" class="space-y-4">
          <.input field={@form[:email]} type="email" label="Email" required />
          <.button>Find user</.button>
        </.form>
        <div
          :if={@selected_user}
          id="admin-selected-user"
          class="rounded-xl border border-slate-200 p-5"
        >
          <p class="font-medium">{@selected_user.email}</p>
          <p class="mt-1 text-sm text-slate-600">Role: {@selected_user.role}</p>
          <button
            id="admin-toggle-role"
            type="button"
            phx-click="set-role"
            phx-value-id={@selected_user.id}
            phx-value-role={if @selected_user.role == :admin, do: "user", else: "admin"}
            data-confirm="Change this user's administrator access?"
            class="mt-4 rounded-lg bg-slate-900 px-4 py-2 text-sm font-medium text-white transition hover:bg-slate-700"
          >
            {if @selected_user.role == :admin, do: "Remove administrator", else: "Grant administrator"}
          </button>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
