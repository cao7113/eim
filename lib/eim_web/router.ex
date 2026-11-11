defmodule EimWeb.Router do
  use EimWeb, :router

  import Oban.Web.Router
  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EimWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
    plug :store_vocab_return_to
  end

  pipeline :api do
    plug :accepts, ["json"]

    plug AshAuthentication.Strategy.ApiKey.Plug,
      resource: Eim.Accounts.User,
      # if you want to require an api key to be supplied, set `required?` to true
      required?: false

    plug :load_from_bearer
    plug :set_actor, :user
    plug :require_vocab_actor
  end

  defp require_vocab_actor(%{request_path: "/api/vocab/" <> _} = conn, _opts) do
    if Ash.PlugHelpers.get_actor(conn) do
      conn
    else
      conn
      |> Plug.Conn.send_resp(:unauthorized, "Authentication required")
      |> Plug.Conn.halt()
    end
  end

  defp require_vocab_actor(conn, _opts), do: conn

  defp store_vocab_return_to(%{request_path: "/learn/vocab"} = conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      return_to =
        conn.request_path <> if(conn.query_string == "", do: "", else: "?" <> conn.query_string)

      Plug.Conn.put_session(conn, :return_to, return_to)
    end
  end

  defp store_vocab_return_to(conn, _opts), do: conn

  scope "/", EimWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes,
      on_mount: [{EimWeb.LiveUserAuth, :live_user_required}] do
      live "/learn/vocab", VocabLive, :index

      # in each liveview, add one of the following at the top of the module:
      #
      # If an authenticated user must be present:
      # on_mount {EimWeb.LiveUserAuth, :live_user_required}
      #
      # If an authenticated user *may* be present:
      # on_mount {EimWeb.LiveUserAuth, :live_user_optional}
      #
      # If an authenticated user must *not* be present:
      # on_mount {EimWeb.LiveUserAuth, :live_no_user}
    end
  end

  scope "/", EimWeb do
    pipe_through :browser

    get "/", PageController, :home

    get "/extension/authorize", ExtensionAuthController, :authorize
    auth_routes AuthController, Eim.Accounts.User, path: "/auth"

    sign_out_route AuthController, "/sign-out",
      overrides: [EimWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    # Remove these if you'd like to use your own authentication views
    sign_in_route register_path: "/register",
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{EimWeb.LiveUserAuth, :live_no_user}],
                  overrides: [EimWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    # Remove this if you do not want to use the reset password feature
    reset_route auth_routes_prefix: "/auth",
                overrides: [EimWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    # Remove this if you do not use the confirmation strategy
    confirm_route Eim.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [EimWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    # Remove this if you do not use the magic link strategy.
    magic_sign_in_route(Eim.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [EimWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]
    )
  end

  scope "/api" do
    pipe_through [:api]

    post "/extension/token", EimWeb.ExtensionAuthController, :exchange
    get "/extension/me", EimWeb.ExtensionAuthController, :me
    delete "/extension/session", EimWeb.ExtensionAuthController, :revoke

    forward "/swaggerui", OpenApiSpex.Plug.SwaggerUI,
      path: "/api/open_api",
      default_model_expand_depth: 4

    forward "/", EimWeb.AshJsonApiRouter
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:eim, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: EimWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    scope "/" do
      pipe_through :browser

      oban_dashboard("/oban")
    end
  end

  if Application.compile_env(:eim, :dev_routes) do
    import AshAdmin.Router

    scope "/admin" do
      pipe_through :browser

      ash_admin "/"
    end
  end
end
