defmodule NanoCluster.JobQueue.Worker do
  @moduledoc """
  The process that will poll the leader's queue for jobs, and then executes them and sends the result back.
  """

  use GenServer

  alias NanoCluster.Network
  alias NanoCluster.JobQueue
  alias NanoCluster.Task

  @poll_delay 100
  @doc """
  Starts the server. `opts` are passed through to `GenServer.start_link/3`,
  so pass `name:` to register a singleton.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # ---------------------------------------------------------------------------#
  #                                API                                         #
  # ---------------------------------------------------------------------------#

  # ---------------------------------------------------------------------------#
  #                                Callbacks                                   #
  # ---------------------------------------------------------------------------#

  @impl true
  def init(_opts) do
    :timer.send_after(@poll_delay, :poll)
    {:ok, %{}}
  end

  @impl true
  def handle_info({:execute_task, :queue_empty}, state) do
    {:noreply, state}
  end

  def handle_info({:execute_task, task, lease, from}, state) do
    MyLogger.info("Computing task")
    task = Task.execute(task)

    try_send({JobQueue, from}, {:task_executed, task, lease})

    {:noreply, state}
  end

  def handle_info(:poll, state) do
    :timer.send_after(@poll_delay, :poll)
    leader = Network.leader()

    if leader == node() do
      {:noreply, state}
    else
      MyLogger.debug("Polling for work @ #{inspect(leader)}")
      # fetch a task from the leader
      try_send({JobQueue, leader}, {:take_task, self()})
      {:noreply, state}
    end
  end

  # ---------------------------------------------------------------------------#
  #                                Helpers                                     #
  # ---------------------------------------------------------------------------#

  defp try_send(to, message) do
    send(to, message)
  catch
    # swallows :error, :exit, and :throw
    _kind, _reason -> :ok
  end
end
