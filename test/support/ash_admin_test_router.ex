defmodule EimWeb.AshAdminTestRouter do
  use Phoenix.Router
  import AshAdmin.Router

  admin_browser_pipeline(:browser)

  scope "/" do
    pipe_through :browser
    ash_admin "/admin"
  end
end
