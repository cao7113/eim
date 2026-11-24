defmodule Mix.Tasks.Dev.Admin do
  use Mix.Task

  alias Eim.Ops

  @shortdoc "Bootstraps the master administrator"

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_args) do
    unless Mix.env() == :dev do
      Mix.raise("mix dev.admin can only be run in the dev environment")
    end

    Ops.bootstrap_master_admin()
  end
end
