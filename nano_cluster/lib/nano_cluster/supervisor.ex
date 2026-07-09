defmodule NanoCluster.Supervisor do
  @moduledoc """
  Top-level supervisor for the node's long-lived processes.

  Owns the five singletons a running node is made of - the peer/leader
  registry, UDP discovery, the job queue, the polling worker, and the HTTP API -
  so a crash in any one of them (a dropped dist connection, an unexpected
  message) is a local restart instead of a VM halt. Previously each was `start_link`'d
  straight from the boot process, which linked them to it; on AtomVM the boot
  process dying takes the whole VM down, so one bad message anywhere was fatal.

  WiFi association and Erlang distribution are bootstrapped in
  `NanoCluster.start/0` *before* this starts. They are one-shot prerequisites,
  not restartable children (there is no address or node name to hand a child
  until they succeed), and `epmd` deliberately stays linked to the boot
  process - see `NanoCluster.Distribution`.
  """

  use Supervisor

  alias NanoCluster.Discovery
  alias NanoCluster.JobQueue
  alias NanoCluster.JobQueue.Worker
  alias NanoCluster.Network
  alias NanoCluster.Web

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Supervisor
  def init(_opts) do
    children = [
      # Network first: Discovery and Worker reach it by its registered name.
      {Network, []},
      # Discovery notifies Network by name, not pid, so a Network restart
      # doesn't strand it holding a dead pid.
      {Discovery, subscriber: Network},
      {JobQueue, []},
      {Worker, []},
      # Last: the HTTP API reads Network and JobQueue, so they come up first.
      {Web, []}
    ]

    # one_for_one: these processes talk to each other by registered name and
    # tolerate a peer restarting under them, so a crash need only restart the
    # process that died.
    Supervisor.init(children, strategy: :one_for_one)
  end
end
