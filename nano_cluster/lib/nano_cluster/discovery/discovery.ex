defmodule NanoCluster.Discovery do
  @moduledoc """
  A process that will periodically announce this node's presence on the network over UDP.
  """
  use GenServer

  alias NanoCluster.Discovery.UDP

  @typedoc "Server state: the multicast socket, this node's name, and the process notified of discovered peers."
  @type state :: %{
          socket: :socket.socket(),
          name: binary(),
          subscriber: pid()
        }

  @announce_interval_ms 500

  @doc """
  Start discovery, linked to the calling process.

  Multicasts this node's name every #{@announce_interval_ms}ms and sends
  `{:announced, peer :: node()}` to `subscriber` for every announcement heard
  from a node other than this one. Call after distribution is up: the
  announced name is `node/0`. Registers under the `:name` option, defaulting
  to `#{inspect(__MODULE__)}`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # reuseaddr lets several AtomVM nodes on one host share the port when
  # testing on a workstation; on a board it is harmless.
  @impl GenServer
  def init(opts) do
    # subscriber process that wants to be notified of new subscriptions.
    subscriber = opts[:subscriber]

    # Setup the UDP socket for broadcasting our presence.
    socket = UDP.broadcast_socket()
    name = :erlang.list_to_binary(:erlang.atom_to_list(node()))

    state = %{socket: socket, name: name, subscriber: subscriber}

    drain(state)
    send(self(), :announce)

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:announce, state) do
    UDP.announce(state.socket, state.name)
    :timer.send_after(@announce_interval_ms, :announce)
    {:noreply, state}
  end

  def handle_info({:"$socket", _socket, :select, _ref}, state) do
    drain(state)
    {:noreply, state}
  end

  def handle_info(other, state) do
    MyLogger.warning("Discovery unexpected message: #{inspect(other)}")
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------#
  #                                Helpers                                     #
  # ---------------------------------------------------------------------------#

  # Drains the UDP socket for announcements. Each announcement is handled. When
  # the socket contains no more announcements, it will return a `{:select..}`.
  # This is "arming" the socket. As soon as the next frame arrives it will be
  # sent to this process as a plain message.
  defp drain(state) do
    case :socket.recvfrom(state.socket, 0, :nowait) do
      {:ok, {_source, data}} ->
        peer = :erlang.list_to_atom(:erlang.binary_to_list(data))

        if peer != node() do
          handle_announcement(peer, state.subscriber)
        end

        drain(state)

      {:select, _select_info} ->
        :ok

      {:error, _reason} = error ->
        MyLogger.error("error discovery recvfrom: #{inspect(error)}")
        :ok
    end
  end

  # notifies the subscribing process of a discovery.
  # This can be a node that was already seen or not.
  defp handle_announcement(peer, subscriber) do
    send(subscriber, {:discovered, peer})
  end
end
