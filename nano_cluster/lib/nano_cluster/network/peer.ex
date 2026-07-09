defmodule NanoCluster.Network.Peer do
  @moduledoc """
  Struct to define the status of a single peer.
  """

  alias NanoCluster.Network.Peer

  @enforce_keys [:node, :alive?, :last_seen]
  defstruct [:node, :alive?, :last_seen]

  @type t :: %Peer{node: node(), alive?: boolean(), last_seen: integer()}

  @doc """
  A peer seen right now: alive, with `last_seen` set to the current
  monotonic time.
  """
  @spec new(node()) :: t()
  def new(node) do
    %Peer{node: node, alive?: true, last_seen: System.monotonic_time()}
  end

  @doc """
  Refreshes the peer: alive again, with `last_seen` reset to now.
  """
  @spec mark_seen(t()) :: t()
  def mark_seen(%Peer{} = peer) do
    %Peer{peer | alive?: true, last_seen: System.monotonic_time()}
  end

  @doc """
  Marks the peer as no longer alive. `last_seen` keeps its old value.
  """
  @spec mark_offline(t()) :: t()
  def mark_offline(%Peer{} = peer) do
    %Peer{peer | alive?: false}
  end

  @doc """
  Whether the peer is currently considered alive.
  """
  @spec alive?(t()) :: boolean()
  def alive?(%Peer{alive?: alive?}), do: alive?

  @doc """
  The peer's liveness as a status atom: `:online` or `:offline`.
  """
  @spec status(t()) :: :online | :offline
  def status(%Peer{alive?: true}), do: :online
  def status(%Peer{alive?: false}), do: :offline

  @doc """
  The monotonic timestamp of the last sighting.
  """
  @spec last_seen(t()) :: integer()
  def last_seen(%Peer{last_seen: last_seen}), do: last_seen

  @doc """
  Milliseconds since the peer was last seen, rounded up.
  """
  @spec age_ms(t()) :: non_neg_integer()
  def age_ms(%Peer{last_seen: last_seen}) do
    ceil((System.monotonic_time() - last_seen) / 1_000_000)
  end
end
