defmodule NanoCluster.Network do
  @moduledoc """
  A process that will keep an eye out for other nodes in the network and
  check if they're still live or not. Also decides the cluster leader: the
  highest-named node currently online, this one included.
  """
  use GenServer

  alias NanoCluster.Network.Peers

  @typedoc "A peer's liveness record: when it last announced (monotonic, native units) and whether it is alive."
  @type peer_info :: %{last_seen: integer(), alive?: boolean()}

  @typedoc "Server state: liveness records for the known peers, plus the sweep timings."
  @type state :: %{
          peers: Peers.t(),
          sweep_interval_ms: pos_integer(),
          offline_threshold_ms: pos_integer()
        }

  # The threshold spans 2.5 discovery announcements (2s apart), so a peer
  # goes offline only after missing two in a row - a single lost packet
  # must not swing the leadership.
  @sweep_interval_ms 2_000
  @offline_threshold_ms 5_000

  @doc """
  Start the network server.

  Registers under the `:name` option, defaulting to `#{inspect(__MODULE__)}`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # ---------------------------------------------------------------------------#
  #                                API                                         #
  # ---------------------------------------------------------------------------#

  @doc """
  The known peers and their liveness, as a map of `node() => :online | :offline`.
  """
  @spec statuses(GenServer.server()) :: %{node() => :online | :offline}
  def statuses(server \\ __MODULE__) do
    GenServer.call(server, :statuses)
  end

  @doc """
  The cluster leader: the highest-named online node, this node included.

  There are no election messages - every node computes the leader from its
  own liveness view, which picks the same node the bully algorithm would
  (the highest one standing) once views agree.
  """
  @spec leader(GenServer.server()) :: node()
  def leader(server \\ __MODULE__) do
    GenServer.call(server, :leader)
  end

  @doc """
  A one-shot snapshot of this node's view of the cluster: its own name, the
  leader it sees, and every known peer's liveness.

  Taken in the server so the leader and the peer statuses can't disagree, which
  a separate `leader/1` + `statuses/1` pair could. This is what the web API
  serves as `GET /api/network`.
  """
  @spec view(GenServer.server()) :: %{
          node: node(),
          leader: node(),
          peers: %{node() => :online | :offline}
        }
  def view(server \\ __MODULE__) do
    GenServer.call(server, :view)
  end

  # ---------------------------------------------------------------------------#
  #                                Callbacks                                   #
  # ---------------------------------------------------------------------------#

  # Timings are overridable so tests don't have to wait out the real sweep.
  @impl GenServer
  def init(opts) do
    state = %{
      peers: Peers.new(),
      sweep_interval_ms: Keyword.get(opts, :sweep_interval_ms, @sweep_interval_ms),
      offline_threshold_ms: Keyword.get(opts, :offline_threshold_ms, @offline_threshold_ms)
    }

    :timer.send_after(state.sweep_interval_ms, :sweep)
    {:ok, state}
  end

  @impl GenServer
  # returns the status of all the known peers in the network.
  def handle_call(:statuses, _from, state) do
    {:reply, Map.new(Peers.statuses(state.peers)), state}
  end

  # returns the current leader in the network.
  def handle_call(:leader, _from, state) do
    {:reply, Peers.leader(state.peers), state}
  end

  # returns this node's whole view of the cluster in one consistent snapshot.
  def handle_call(:view, _from, state) do
    view = %{
      node: node(),
      leader: Peers.leader(state.peers),
      peers: Map.new(Peers.statuses(state.peers))
    }

    {:reply, view, state}
  end

  @impl GenServer
  # handles a discovered peer. this can be a known or new peer.
  def handle_info({:discovered, peer}, state) do
    MyLogger.debug("Discovered peer: #{inspect(peer)}")
    {:noreply, %{state | peers: Peers.mark_seen(state.peers, peer)}}
  end

  # sweeps all peers for their liveness status.
  def handle_info(:sweep, state) do
    peers = Peers.mark_stale_offline(state.peers, state.offline_threshold_ms)
    state = %{state | peers: peers}
    :timer.send_after(state.sweep_interval_ms, :sweep)
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------#
  #                                Helpers                                     #
  # ---------------------------------------------------------------------------#
end
