defmodule VmMonitoringWeb.PageController do
  use VmMonitoringWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
