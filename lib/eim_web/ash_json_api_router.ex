defmodule EimWeb.AshJsonApiRouter do
  use AshJsonApi.Router,
    domains: [Eim.Dict],
    open_api: "/open_api"
end
