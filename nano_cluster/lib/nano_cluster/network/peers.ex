defmodule NanoCluster.Network.Peers do
  @moduledoc """
  The set of known peers, keyed by node name, with liveness bookkeeping.

  This struct basically represents the current's node view of the network. Which
  peers are online, which are offline.
  """

  alias NanoCluster.Network.Peer
  alias NanoCluster.Network.Peers

  defstruct entries: %{}

  @type t :: %Peers{entries: %{node() => Peer.t()}}

  @spec new() :: t()
  def new, do: %Peers{}

  @doc """
  Returns the leader of this peer set: the highest-named node standing,
  the current node included. With no other live peer that is the current
  node itself.
  """
  @spec leader(t()) :: node()
  def leader(%Peers{} = peers) do
    # Enum.reduce + a hand-rolled max: the device image's Enum has no max/1
    peers
    |> online_peers()
    |> Enum.reduce(node(), &max_node/2)
  end

  @doc """
  Records a sighting of `node`: refreshes the peer if known, adds a
  fresh alive one otherwise.
  """
  @spec mark_seen(t(), node()) :: t()
  def mark_seen(%Peers{} = peers, node) do
    updated_peer =
      peers.entries
      |> Map.get(node, Peer.new(node))
      |> Peer.mark_seen()

    entries = Map.put(peers.entries, node, updated_peer)
    %Peers{peers | entries: entries}
  end

  @doc """
  Marks a known peer offline; an unknown node is left alone.
  """
  @spec mark_offline(t(), node()) :: t()
  def mark_offline(%Peers{} = peers, node) do
    case Map.fetch(peers.entries, node) do
      {:ok, peer} -> put(peers, node, Peer.mark_offline(peer))
      :error -> peers
    end
  end

  @doc """
  Whether `node` is known and currently considered alive.
  """
  @spec alive?(t(), node()) :: boolean()
  def alive?(%Peers{} = peers, node) do
    case Map.fetch(peers.entries, node) do
      {:ok, peer} -> Peer.alive?(peer)
      :error -> false
    end
  end

  @doc """
  The alive peers whose last sighting is older than `threshold_ms`.
  """
  @spec stale_peers(t(), non_neg_integer()) :: [node()]
  def stale_peers(%Peers{} = peers, threshold_ms) do
    for {node, peer} <- peers.entries,
        Peer.alive?(peer),
        Peer.age_ms(peer) > threshold_ms,
        do: node
  end

  @doc """
  Marks every alive peer older than `threshold_ms` as offline.

  Call `stale/2` first when the caller needs to know who is about to
  go offline (e.g. to log the transition).
  """
  @spec mark_stale_offline(t(), non_neg_integer()) :: t()
  def mark_stale_offline(%Peers{} = peers, threshold_ms) do
    peers
    |> stale_peers(threshold_ms)
    |> Enum.reduce(peers, fn node, acc -> mark_offline(acc, node) end)
  end

  @doc """
  Every known peer with its liveness, as `[{node, :online | :offline}]`.
  """
  @spec statuses(t()) :: [{node(), :online | :offline}]
  def statuses(%Peers{} = peers) do
    for {node, peer} <- peers.entries, do: {node, Peer.status(peer)}
  end

  @doc """
  The nodes currently considered alive.
  """
  @spec online_peers(t()) :: [node()]
  def online_peers(%Peers{} = peers) do
    for {node, peer} <- peers.entries, Peer.alive?(peer), do: node
  end

  defp put(%Peers{} = peers, node, peer) do
    %Peers{peers | entries: Map.put(peers.entries, node, peer)}
  end

  defp max_node(a, b) when a > b, do: a
  defp max_node(_a, b), do: b
end
