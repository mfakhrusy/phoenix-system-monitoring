defmodule VmMonitoringWeb.VmLive do
  use VmMonitoringWeb, :live_view
  require Logger

  def mount(_params, _session, socket) do
    Logger.info("Mounting DomainLive...")

    if connected?(socket) do
      # subscribe to the poller
      Phoenix.PubSub.subscribe(VmMonitoring.PubSub, "vm:update")
      send(self(), :load_domains)
    end
    {:ok,
      assign(socket,
        domains: [],
        host_info: nil,
        error: nil,
        loading: true,
        cpu_percents: []
      ),
      temporary_assigns: [domains: []]
    }
  end

  def handle_info(:load_domains, socket) do
    socket = fetch_data(socket)
    {:noreply, socket}
  end

  # ---------- handle_info from poller ----------
  def handle_info({:vm_update, domains, host_info}, socket) do
    percents = host_info && host_to_percents(host_info)
    # Logger.info(host_info)
    socket =
      socket
      |> assign(domains: domains, host_info: host_info, loading: false, error: nil)
      |> assign(:cpu_percents, percents)

    {:noreply, socket}
  end

  # ---------- helper: convert host samples → per-cpu % ----------
  defp host_to_percents(%{time: samples}), do: Enum.map(samples, & &1.percent)

  defp fetch_data(socket) do
    case LibvirtNif.connect(~c"qemu:///system") do
      {:ok, conn} ->
        result_domains = LibvirtNif.list_domains(conn)
        result_host = LibvirtNif.get_host_info(conn)
        LibvirtNif.disconnect(conn)

        case {result_domains, result_host} do
          {{:ok, domains}, {:ok, host_info}} ->
            # Logger.info(host_info)
            assign(socket, domains: domains, host_info: host_info, error: nil, loading: false)
          {_, {:error, reason}} ->
            assign(socket, domains: [], host_info: nil, error: reason, loading: false)
          {{:error, reason}, _} ->
            assign(socket, domains: [], host_info: nil, error: reason, loading: false)
        end

      {:error, reason} ->
        assign(socket, domains: [], error: reason, loading: false)
    end
  end

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
                <span class="w-12 text-right mr-8">CPU<%= cpu %></span>
                <div class="flex-1 bg-gray-200 h-4 rounded overflow-hidden">
                  <div class="bg-green-500 h-full" style={"width:#{pct}%"}></div>
                </div>
                <span class="w-16"><%= :erlang.float_to_binary(pct * 1.0, decimals: 2) %>%</span>
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
            Error: <%= @error %>
          </div>
        <% end %>

        <div class="grid gap-4">
          <%= for domain <- @domains do %>
            <div class="border rounded-lg p-4 shadow">
              <h2 class="text-xl font-semibold"><%= domain.name %></h2>
              <div class="mt-2 space-y-1">
                <p><strong>ID:</strong> <%= domain.id %></p>
                <p><strong>Memory:</strong> <%= div(domain.memory, 1024) %> MB</p>
                <p><strong>CPU Time:</strong> <%= domain.cpu_time %></p>
                <p><strong>State:</strong> <%= domain.state %></p>
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
    {:ok, %{prev: nil}}
  end

  def handle_info(:tick, %{prev: prev} = state) do
    Process.send_after(self(), :tick, @interval)

    case LibvirtNif.connect(~c"qemu:///system") do
      {:ok, conn} ->
        with {:ok, domains} <- LibvirtNif.list_domains(conn),
             {:ok, host}    <- LibvirtNif.get_host_info(conn) do
          LibvirtNif.disconnect(conn)

          {host_with_util, new_prev} = calc_util(prev, host)
          Phoenix.PubSub.broadcast(
            VmMonitoring.PubSub,
            "vm:update",
            {:vm_update, domains, host_with_util}
          )
          {:noreply, %{state | prev: new_prev}}
        else
          err ->
            LibvirtNif.disconnect(conn)
            Logger.warning("Poller fetch error: #{inspect(err)}")
            Phoenix.PubSub.broadcast(
              VmMonitoring.PubSub,
              "vm:update",
              {:vm_update, [], nil}
            )
            {:noreply, state}
        end

      {:error, reason} ->
        Logger.warning("Poller connect error: #{inspect(reason)}")
        Phoenix.PubSub.broadcast(
          VmMonitoring.PubSub,
          "vm:update",
          {:vm_update, [], nil}
        )
        {:noreply, state}
    end
  end

  # ---------- helpers ----------
  defp calc_util(nil, %{time: samples} = host) do
    # first tick – no delta yet, report 0 %
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
        busy = (t2 - t1) - (i2 - i1)
        tot  = t2 - t1
        pct  = if tot == 0, do: 0.0, else: busy / tot * 100

        {Map.put(p_acc, idx, {t2, i2}), [Map.put(s, :percent, pct) | u_acc]}
      end)

    {put_in(host.time, Enum.reverse(util_list)), new_prev}
  end

end
