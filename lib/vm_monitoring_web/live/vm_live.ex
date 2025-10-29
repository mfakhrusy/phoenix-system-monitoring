defmodule VmMonitoringWeb.VmLive do
  use VmMonitoringWeb, :live_view
  require Logger

  def mount(_params, _session, socket) do
    Logger.info("Mounting DomainLive...")

    if connected?(socket) do
      Phoenix.PubSub.subscribe(VmMonitoring.PubSub, "vm:update")

      # Establish a single persistent libvirt connection for this LiveView process
      case LibvirtNif.connect(~c"qemu:///system") do
        {:ok, conn} ->
          send(self(), :load_domains)

          {:ok,
           assign(socket,
             conn: conn,
             domains: [],
             host_info: nil,
             error: nil,
             loading: true,
             cpu_percents: []
           ), temporary_assigns: [domains: []]}

        {:error, reason} ->
          {:ok, assign(socket, error: "Failed to connect: #{reason}", loading: false)}
      end
    else
      # Not yet connected — mount phase before the socket is alive
      {:ok,
       assign(socket,
         conn: nil,
         domains: [],
         host_info: nil,
         error: nil,
         loading: true,
         cpu_percents: []
       ), temporary_assigns: [domains: []]}
    end
  end

  def handle_info(:load_domains, socket) do
    socket = fetch_data(socket)
    {:noreply, socket}
  end

  # ---------- handle_info from poller ----------
  def handle_info({:vm_update, domains, host_info}, socket) do
    percents = host_info && host_to_percents(host_info)

    socket =
      socket
      |> assign(domains: domains, host_info: host_info, loading: false, error: nil)
      |> assign(:cpu_percents, percents)

    {:noreply, socket}
  end

  def handle_event("shutdown_domain", %{"name" => name}, socket) do
    conn = ensure_conn(socket.assigns[:conn])

    Logger.info(name)

    if conn do
      case LibvirtNif.domain_shutdown(conn, name) do
        {:ok, _} ->
          {:noreply, put_flash(socket, :info, "Shutdown requested")}

        {:error, e} ->
          {:noreply, put_flash(socket, :error, "Shutdown failed: #{e}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Failed to connect to libvirt")}
    end
  end

  # def handle_event("start_domain", %{"uuid" => uuid}, socket) do
  #   case Map.fetch(socket.assigns.domain_refs, uuid) do
  #     {:ok, ref} ->
  #       case LibvirtNif.domain_create(ref) do
  #         {:ok, _} -> {:noreply, put_flash(socket, :info, "Domain started")}
  #         {:error, e} -> {:noreply, put_flash(socket, :error, "Start: #{e}")}
  #       end

  #     :error ->
  #       {:noreply, put_flash(socket, :error, "Domain ref not found")}
  #   end
  # end

  # ---------- helper: convert host samples → per-cpu % ----------
  defp host_to_percents(%{time: samples}), do: Enum.map(samples, & &1.percent)

  defp ensure_conn(nil) do
    case LibvirtNif.connect(~c"qemu:///system") do
      {:ok, conn} ->
        Logger.info("Reconnected to libvirt.")
        conn

      {:error, reason} ->
        Logger.warning("Failed to reconnect to libvirt: #{inspect(reason)}")
        nil
    end
  end

  defp ensure_conn(conn), do: conn

  defp fetch_data(socket) do
    conn = ensure_conn(socket.assigns[:conn])

    if conn do
      result_domains = LibvirtNif.list_domains(conn)
      result_host = LibvirtNif.get_host_info(conn)

      case {result_domains, result_host} do
        {{:ok, domains}, {:ok, host_info}} ->
          assign(socket,
            conn: conn,
            domains: domains,
            host_info: host_info,
            error: nil,
            loading: false
          )

        _ ->
          assign(socket,
            conn: conn,
            domains: [],
            host_info: nil,
            error: "Fetch failed",
            loading: false
          )
      end
    else
      assign(socket,
        conn: nil,
        domains: [],
        host_info: nil,
        error: "No connection",
        loading: false
      )
    end
  end

  defp domain_state(0), do: "no state"
  defp domain_state(1), do: "running"
  defp domain_state(2), do: "blocked"
  defp domain_state(3), do: "paused"
  defp domain_state(4), do: "shutdown"
  defp domain_state(5), do: "shut off"
  defp domain_state(6), do: "crashed"
  defp domain_state(7), do: "pm suspended"
  defp domain_state(_), do: "unknown"

  def render(assigns) do
    ~H"""
    <div class="">
      <div class="p-8">
        <div class="flex justify-between items-center mb-6">
          <h2 class="text-3xl font-bold">Host</h2>
        </div>

        <%= if @cpu_percents != [] do %>
          <div class="mt-4 grid grid-cols-1 gap-2">
            <%= for {pct, cpu} <- Enum.with_index(@cpu_percents) do %>
              <div class="flex items-center gap-2">
                <span class="w-12 text-right mr-8">CPU{cpu}</span>
                <div class="flex-1 bg-gray-200 h-4 rounded overflow-hidden">
                  <div class="bg-green-500 h-full" style={"width:#{pct}%"}></div>
                </div>
                <span class="w-16">{:erlang.float_to_binary(pct * 1.0, decimals: 2)}%</span>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <div class="p-8">
        <div class="flex justify-between items-center mb-6 flex-column">
          <h2 class="text-3xl font-bold">Virtual Machines</h2>
        </div>

        <%= if @loading do %>
          <p>Loading...</p>
        <% end %>

        <%= if @error do %>
          <div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded">
            Error: {@error}
          </div>
        <% end %>

        <div class="grid gap-4">
          <%= for domain <- @domains do %>
            <div class="border rounded-lg p-4 shadow">
              <h2 class="text-xl font-semibold">{domain.name}</h2>
              <div class="mt-2 space-y-1">
                <p><strong>Memory:</strong> {div(domain.memory, 1024)} MB</p>
                <p><strong>CPU Time:</strong> {domain.cpu_time}</p>
                <p><strong>State:</strong> {domain_state(domain.state)}</p>
              </div>
              <div class="flex gap-2 mt-4">
                <%= if domain_state(domain.state) == "paused" || domain_state(domain.state) == "shut off" do %>
                  <button
                    phx-click="start_domain"
                    phx-value-name={domain.name}
                    class="px-3 py-1 bg-green-600 text-white rounded hover:bg-green-700"
                  >
                    Start
                  </button>
                <% end %>
                <%= if domain_state(domain.state) == "running" do %>
                  <button
                    phx-click="shutdown_domain"
                    phx-value-name={domain.name}
                    class="px-3 py-1 bg-red-600 text-white rounded hover:bg-red-700"
                  >
                    Shut down
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end

defmodule VmMonitoringWeb.VmLive.Poller do
  use GenServer, restart: :transient
  require Logger

  @interval 1_000

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def init(_) do
    Process.send_after(self(), :tick, 0)
    {:ok, %{conn: nil, prev: nil}}
  end

  def handle_info(:tick, %{conn: conn, prev: prev} = state) do
    Process.send_after(self(), :tick, @interval)

    conn =
      case conn do
        nil ->
          case LibvirtNif.connect(~c"qemu:///system") do
            {:ok, new_conn} ->
              Logger.info("Poller connected to libvirt.")
              new_conn

            {:error, reason} ->
              Logger.warning("Poller failed to connect: #{inspect(reason)}")
              Phoenix.PubSub.broadcast(VmMonitoring.PubSub, "vm:update", {:vm_update, [], nil})
              return_noop(state)
          end

        conn_ref ->
          conn_ref
      end

    # Proceed if we have a valid connection
    case {LibvirtNif.list_domains(conn), LibvirtNif.get_host_info(conn)} do
      {{:ok, domains}, {:ok, host}} ->
        {host_with_util, new_prev} = calc_util(prev, host)

        Phoenix.PubSub.broadcast(
          VmMonitoring.PubSub,
          "vm:update",
          {:vm_update, domains, host_with_util}
        )

        {:noreply, %{state | conn: conn, prev: new_prev}}

      {_, {:error, reason}} ->
        Logger.warning("Poller host info error: #{inspect(reason)}")
        LibvirtNif.disconnect(conn)
        Phoenix.PubSub.broadcast(VmMonitoring.PubSub, "vm:update", {:vm_update, [], nil})
        {:noreply, %{state | conn: nil}}

      {{:error, reason}, _} ->
        Logger.warning("Poller domain list error: #{inspect(reason)}")
        LibvirtNif.disconnect(conn)
        Phoenix.PubSub.broadcast(VmMonitoring.PubSub, "vm:update", {:vm_update, [], nil})
        {:noreply, %{state | conn: nil}}
    end
  end

  defp return_noop(state) do
    {:noreply, %{state | conn: nil}}
  end

  # ---------- helpers ----------
  defp calc_util(nil, %{time: samples} = host) do
    prev =
      samples
      |> Enum.with_index()
      |> Map.new(fn {%{total: t, idle: i}, idx} -> {idx, {t, i}} end)

    zeroed = Enum.map(samples, &Map.put(&1, :percent, 0.0))
    {%{host | time: zeroed}, prev}
  end

  defp calc_util(prev, %{time: samples} = host) do
    {new_prev, util_list} =
      samples
      |> Enum.with_index()
      |> Enum.reduce({%{}, []}, fn {%{total: t2, idle: i2} = s, idx}, {p_acc, u_acc} ->
        {t1, i1} = Map.get(prev, idx, {t2, i2})
        busy = t2 - t1 - (i2 - i1)
        tot = t2 - t1
        pct = if tot == 0, do: 0.0, else: busy / tot * 100

        {Map.put(p_acc, idx, {t2, i2}), [Map.put(s, :percent, pct) | u_acc]}
      end)

    {put_in(host.time, Enum.reverse(util_list)), new_prev}
  end
end
