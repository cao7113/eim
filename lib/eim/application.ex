defmodule Eim.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      EimWeb.Telemetry,
      Eim.Repo,
      {Oban,
       AshOban.config(
         Application.fetch_env!(:eim, :ash_domains),
         Application.fetch_env!(:eim, Oban)
       )},
      # Start a worker by calling: Eim.Worker.start_link(arg)
      # {Eim.Worker, arg},
      # Start to serve requests, typically the last entry
      {DNSCluster, query: Application.get_env(:eim, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Eim.PubSub},
      EimWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :eim]}
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Eim.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EimWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
