defmodule NanoCluster.Discovery.UDP do
  @moduledoc """
  Thin wrapper around `:socket` for multicast UDP discovery: opens a reusable
  socket joined to the multicast group and announces this node's name on it.
  """

  @group {239, 255, 42, 99}
  @port 4573

  @doc """
  Opens up the broadcast socket. The UDP socket will join the multicast group to
  listen for broadcasts from other devices.
  """
  @spec broadcast_socket() :: :socket.socket()
  def broadcast_socket do
    {:ok, socket} = :socket.open(:inet, :dgram, :udp)
    :ok = :socket.setopt(socket, {:socket, :reuseaddr}, true)
    :ok = :socket.bind(socket, %{family: :inet, addr: {0, 0, 0, 0}, port: @port})

    :ok =
      :socket.setopt(socket, {:ip, :add_membership}, %{
        multiaddr: @group,
        interface: {0, 0, 0, 0}
      })

    socket
  end

  @doc """
  Send a multicast frame over this socket announcing ourselves on the network.
  """
  @spec announce(:socket.socket(), binary()) :: :ok | {:error, term()}
  def announce(socket, name) do
    :socket.sendto(socket, name, %{family: :inet, addr: @group, port: @port})
  end
end
