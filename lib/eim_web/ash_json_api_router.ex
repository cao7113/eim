defmodule EimWeb.AshJsonApiRouter do
  use AshJsonApi.Router,
    domains: [Eim.Dict, Eim.Vocab],
    open_api: "/open_api"
end
