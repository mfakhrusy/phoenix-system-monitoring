defmodule VmMonitoring.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      VmMonitoringWeb.Telemetry,
      # VmMonitoring.Repo,
      {DNSCluster, query: Application.get_env(:vm_monitoring, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: VmMonitoring.PubSub},
      # Start a worker by calling: VmMonitoring.Worker.start_link(arg)
      # {VmMonitoring.Worker, arg},
      # Start to serve requests, typically the last entry
      VmMonitoringWeb.Endpoint,
      VmMonitoringWeb.VmLive.Poller,
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: VmMonitoring.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    VmMonitoringWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
