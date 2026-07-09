defmodule NanoCluster.Distribution do
  @moduledoc """
  Erlang distribution on AtomVM.

  Starts epmd and net_kernel, naming this node nano@<ip> so peers can dial
  it using the address they hear in discovery announcements.
  """

  # AtomVM ships its own :epmd module and puts set_cookie in :net_kernel;
  # neither exists in host OTP, so silence the cross-compile warnings
  @compile {:no_warn_undefined, [:epmd, {:net_kernel, :set_cookie, 1}]}

  @cookie "AtomVM"

  @doc """
  Start epmd and net_kernel as nano@<address> and set the cluster cookie.

  epmd is linked to the calling process, so call this from a process that
  lives forever. Crashes (match error) if either component fails to start,
  which takes the calling process - and on AtomVM the whole app - down.
  """
  @spec start(NanoCluster.ip_address()) :: :ok | :error
  def start(address) do
    with {:ok, _epmd} <- :epmd.start_link([]),
         node = node_name(address),
         {:ok, _net_kernel} <- :net_kernel.start(node, %{name_domain: :longnames}) do
      :net_kernel.set_cookie(@cookie)
      :io.format(~c"Distribution started, this node is ~p~n", [node()])
      :ok
    else
      _ -> :error
    end
  end

  @doc """
  Re-assert the cluster cookie; safe to call at any time.

  AtomVM's net_kernel is supervised: after a crash it restarts with a
  freshly generated random cookie, and from then on every distribution
  handshake fails with invalid_challenge - the node looks healthy but
  cannot talk to anyone. Calling this periodically self-heals within one
  beat. The catch covers net_kernel being mid-restart.
  """
  @spec reassert_cookie() :: :ok
  def reassert_cookie do
    :net_kernel.set_cookie(@cookie)
    :ok
  catch
    _kind, _reason -> :ok
  end

  @doc """
  The distribution name for a node at `address`.

      iex> NanoCluster.Distribution.node_name({192, 168, 4, 61})
      :"nano@192.168.4.61"

  """
  @spec node_name(NanoCluster.ip_address()) :: node()
  def node_name({a, b, c, d}) do
    :erlang.list_to_atom(:lists.flatten(:io_lib.format(~c"nano@~B.~B.~B.~B", [a, b, c, d])))
  end
end
