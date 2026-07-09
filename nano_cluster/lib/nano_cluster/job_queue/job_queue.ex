defmodule NanoCluster.JobQueue do
  @moduledoc """
  The process that owns a `NanoCluster.Queue`.

  This GenServer is pure boundary: every callback delegates straight to a
  `NanoCluster.Queue` function and stores the result. All the logic — job
  membership, completion, vacuuming — lives in that plain data module, so it
  can be exercised without a process. Talk to the server through
  `NanoCluster.JobQueue.Client`, never by sending it tuples directly.

  Start it under a supervisor with a registered name for the singleton case:

      children = [{NanoCluster.JobQueue.Server, name: NanoCluster.JobQueue.Server}]

  or start an unnamed instance (handy in tests) with `start_link/1` and hand
  the pid to the client functions.
  """

  use GenServer

  alias NanoCluster.Queue
  alias NanoCluster.Job
  alias NanoCluster.JobQueue

  defstruct jobs: %{}, queue: Queue.new(), completed: []

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

  def add_job(job, server \\ __MODULE__) do
    GenServer.call(server, {:add_job, job})
  end

  def add_job_to_leader(job) do
    server = Network.leader()
    add_job(job, {server, __MODULE__})
  end

  def take_task(server \\ __MODULE__) do
    GenServer.call(server, :take_task)
  end

  def put_task_result(task, lease, server \\ __MODULE__) do
    GenServer.call(server, {:put_task, task, lease})
  end

  def job_results(server \\ __MODULE__) do
    GenServer.call(server, :job_results)
  end

  def queue_stats(server \\ __MODULE__) do
    GenServer.call(server, :queue_stats)
  end

  # ---------------------------------------------------------------------------#
  #                                Callbacks                                   #
  # ---------------------------------------------------------------------------#

  @impl true
  def init(_opts) do
    {:ok, %JobQueue{}}
  end

  @impl true
  def handle_call({:add_job, job}, _from, state) do
    # fetch the tasks from the job
    job_id = job.id
    job_tasks = job.tasks

    # add the job tasks to the queue.
    queue = Queue.enqueue_many(state.queue, job_tasks)

    # add the id to the jobs list.
    jobs = Map.put(state.jobs, job_id, job)

    {:reply, :ok, %{state | queue: queue, jobs: jobs}}
  end

  def handle_call(:job_results, _from, state) do
    {:reply, state.completed, state}
  end

  def handle_call(:queue_stats, _from, state) do
    job_count = Enum.count(state.jobs)
    completed_count = Enum.count(state.completed)
    queue_count = Queue.statistics(state.queue)

    {:reply, %{job_count: job_count, completed_count: completed_count, queue_stats: queue_count},
     state}
  end

  @impl true
  def handle_info({:task_executed, task, lease}, state) do
    # tell the queue the task has been completed.
    {:ok, _, queue} = Queue.complete(state.queue, lease)

    # store the result of this task in the job we have locally.
    job = Map.get(state.jobs, task.job_id)
    job = Job.put_complete(job, task)
    jobs = Map.put(state.jobs, task.job_id, job)

    state = %{state | jobs: jobs, queue: queue}

    if Job.complete?(job) do
      MyLogger.info("#{inspect(Job.result(job))}")
      MyLogger.info("Job completed")
      result = %{job_id: job.id, description: job.description, result: Job.result(job)}
      IO.puts(inspect(result))
      completed = [result | state.completed]
      jobs = Map.delete(state.jobs, task.job_id)
      state = %{state | completed: completed, jobs: jobs}
      IO.inspect(state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info({:take_task, from}, state) do
    case Queue.pop(state.queue) do
      {:error, :queue_empty} ->
        try_send(from, {:execute_task, :queue_empty})
        {:noreply, state}

      {:ok, task, lease, queue} ->
        state = %{state | queue: queue}
        try_send(from, {:execute_task, task, lease, node()})
        {:noreply, state}
    end
  end

  defp try_send(to, message) do
    send(to, message)
  catch
    # swallows :error, :exit, and :throw
    _kind, _reason -> :ok
  end
end
