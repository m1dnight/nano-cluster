defmodule NanoCluster do
  @moduledoc """
  Self-discovering AtomVM cluster debug app.

  Every board runs this same app: NanoCluster.Wifi connects using credentials
  from NVS, NanoCluster.Distribution starts this node as nano@<own-ip>, then
  NanoCluster.Discovery announces it over UDP multicast. NanoCluster.Network
  keeps a map of every node it hears from, marking each online/offline as
  signs of life come and go, and calls the highest-named online node the
  cluster leader. New boards join the mesh with zero configuration.
  """

  alias NanoCluster.Distribution
  alias NanoCluster.Network
  alias NanoCluster.Wifi
  alias NanoCluster.JobQueue

  @typedoc "An IPv4 address, as returned by AtomVM's network driver."
  @type ip_address :: {byte(), byte(), byte(), byte()}

  @doc """
  Application entry point; AtomVM boots the module exporting `start/0`.

  Connects to WiFi and starts distribution (one-shot prerequisites), then
  starts the supervision tree that owns the network registry, discovery, job
  queue and worker. Loops forever afterwards. Only returns when no WiFi
  credentials are stored in NVS (nothing useful can run without a network).
  """

  @spec start() :: :ok | no_return()
  def start do
    IO.puts("NanoCluster booting...")

    with {:ok, address} <- Wifi.connect(),
         :ok <- Distribution.start(address),
         {:ok, _sup} <- NanoCluster.Supervisor.start_link([]) do
      IO.puts("Node started")
      # heap_logging()
      run_forever()
    else
      :no_credentials ->
        IO.puts("No WiFi credentials in NVS - run `just set-wifi <ssid> <psk>` first")
    end
  end

  # The work all happens in the GenServers; the boot process only has to
  # stay alive - AtomVM halts the VM when the entry process returns. Each
  # beat it re-asserts the dist cookie, healing the random cookie a
  # restarted net_kernel comes back with.
  @spec run_forever() :: no_return()
  defp run_forever do
    Distribution.reassert_cookie()
    leader = Network.leader()
    # MyLogger.info("Current leader: #{inspect(leader)}")
    :timer.sleep(10_000)
    run_forever()
  end

  defp heap_logging do
    spawn(&debug_log/0)
  end

  defp debug_log do
    IO.inspect(%{
      free_heap_size: :erlang.system_info(:esp32_free_heap_size)
    })

    Process.sleep(500)
    debug_log()
  end
end
