defmodule EimWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use EimWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"
  @dev_routes Application.compile_env(:eim, :dev_routes, false)

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :current_user, :map, default: nil

  slot :inner_block, required: true

  def app(assigns) do
    assigns =
      assigns
      |> assign(:dev_routes_enabled, @dev_routes)
      |> assign(
        :admin?,
        assigns.current_user && Eim.Accounts.Admins.admin?(assigns.current_user.id)
      )

    ~H"""
    <header class="border-b border-slate-200/80 bg-white/90">
      <nav
        aria-label="Main navigation"
        class="mx-auto flex max-w-7xl items-center justify-between px-5 py-4 sm:px-8"
      >
        <a href="/" class="flex items-center gap-2.5" aria-label="Eim home">
          <span class="flex size-9 items-center justify-center rounded-xl bg-slate-950 text-lime-300">
            <.icon name="hero-book-open" class="size-5" />
          </span>
          <span class="text-lg font-semibold tracking-tight text-slate-950">eim</span>
        </a>
        <div class="flex min-w-0 flex-1 flex-wrap items-center justify-end gap-x-3 gap-y-2 sm:gap-6">
          <%= if @dev_routes_enabled do %>
            <div id="dev-tools" class="nav-tools group relative">
              <button
                id="dev-tools-toggle"
                type="button"
                aria-expanded="false"
                aria-controls="dev-tools-menu"
                class="flex cursor-pointer items-center gap-1 text-sm font-semibold text-slate-600 transition hover:text-slate-950 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-lime-700"
              >
                Dev
                <.icon
                  name="hero-chevron-down"
                  class="size-4 transition group-hover:rotate-180 group-focus-within:rotate-180"
                />
              </button>
              <div
                id="dev-tools-menu"
                class="nav-tools-menu absolute right-0 top-full z-50 hidden w-48 pt-2"
              >
                <div class="rounded-xl border border-slate-200 bg-white p-1.5 shadow-lg shadow-slate-950/10">
                  <a
                    href="/dev/dashboard"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="block rounded-lg px-3 py-2 text-sm font-medium text-slate-700 transition hover:bg-slate-100 hover:text-slate-950"
                  >
                    Live Dashboard
                  </a>
                  <a
                    href="/dev/mailbox"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="block rounded-lg px-3 py-2 text-sm font-medium text-slate-700 transition hover:bg-slate-100 hover:text-slate-950"
                  >
                    Mailbox
                  </a>
                  <a
                    href="/api/swaggerui"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="block rounded-lg px-3 py-2 text-sm font-medium text-slate-700 transition hover:bg-slate-100 hover:text-slate-950"
                  >
                    API / Swagger
                  </a>
                </div>
              </div>
            </div>
          <% end %>
          <div :if={@admin?} id="admin-tools" class="nav-tools group relative">
            <button
              id="admin-tools-toggle"
              type="button"
              aria-expanded="false"
              aria-controls="admin-tools-menu"
              class="flex cursor-pointer items-center gap-1 text-sm font-semibold text-slate-600 transition hover:text-slate-950 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-lime-700"
            >
              Admin
              <.icon
                name="hero-chevron-down"
                class="size-4 transition group-hover:rotate-180 group-focus-within:rotate-180"
              />
            </button>
            <div
              id="admin-tools-menu"
              class="nav-tools-menu absolute right-0 top-full z-50 hidden w-48 pt-2"
            >
              <div class="rounded-xl border border-slate-200 bg-white p-1.5 shadow-lg shadow-slate-950/10">
                <a
                  id="admin-dashboard-link"
                  href="/admin"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="block rounded-lg px-3 py-2 text-sm font-medium text-slate-700 transition hover:bg-slate-100 hover:text-slate-950"
                >
                  Admin
                </a>
                <a
                  id="oban-dashboard-link"
                  href="/oban"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="block rounded-lg px-3 py-2 text-sm font-medium text-slate-700 transition hover:bg-slate-100 hover:text-slate-950"
                >
                  Oban
                </a>
              </div>
            </div>
          </div>
          <a
            :if={@current_user}
            id="vocabulary-link"
            href="/learn/vocab"
            class="text-sm font-semibold text-slate-700 transition hover:text-slate-950"
          >
            Vocabulary
          </a>
          <a
            id="dictionary-link"
            href="/dicts/ecdict"
            class="text-sm font-semibold text-slate-700 transition hover:text-slate-950"
          >
            Dictionary
          </a>
          <%= if @current_user do %>
            <span class="flex min-w-0 items-center gap-1 text-sm font-medium text-slate-600">
              <span
                id="current-user-email"
                class="max-w-[9rem] truncate sm:max-w-none"
                title={@current_user.email}
              >
                {@current_user.email}
              </span>
              <span :if={@admin?} id="current-user-admin" class="shrink-0 text-slate-500">
                (admin)
              </span>
            </span>
            <.link
              id="sign-out-link"
              href="/sign-out"
              method="delete"
              class="text-sm font-semibold text-slate-700 transition hover:text-slate-950"
            >
              Sign out
            </.link>
          <% else %>
            <a
              href="/#how-it-works"
              class="hidden text-sm font-medium text-slate-600 transition hover:text-slate-950 sm:block"
            >
              How it works
            </a>
            <a
              href="/sign-in"
              class="text-sm font-semibold text-slate-700 transition hover:text-slate-950"
            >
              Sign in
            </a>
            <a
              href="/register"
              class="rounded-lg bg-slate-950 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-lime-800"
            >
              Get started
            </a>
          <% end %>
          <.theme_toggle />
        </div>
      </nav>
    </header>

    <main class="mx-auto max-w-7xl px-5 sm:px-8">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
