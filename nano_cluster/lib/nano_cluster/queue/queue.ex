defmodule NanoCluster.Queue do
  @moduledoc """
  A queue of work items that can be leased out to worker nodes.

  Items live in one of two places:

    * `todo` — work waiting to be handed out, most recently enqueued first.
    * `pending` — work that has been `pop/1`ed and is now out on a lease,
      keyed by the `lease` reference the worker was handed.

  A worker `pop/1`s an item, does the work, then calls `complete/2` with its
  lease to release it. If the worker never reports back, `sweep/2` reclaims
  leases older than a cutoff and returns their items to `todo` to be handed
  out again. The queue is a plain data structure — it holds no processes and
  performs no timing of its own.
  """

  alias NanoCluster.Queue
  alias NanoCluster.Queue.PendingTask

  @typedoc "The reference a worker is handed for an item it has leased."
  @type lease :: reference()

  @typedoc "A unit of work. Any term is valid."
  @type task :: term()

  @type t :: %__MODULE__{
          todo: [task()],
          pending: %{lease() => PendingTask.t()},
          jobs: map(),
          finished: [task()]
        }

  defstruct todo: [], pending: %{}, jobs: %{}, finished: []

  @doc """
  Returns a new, empty queue.
  """
  @spec new() :: t()
  def new do
    %Queue{}
  end

  def statistics(queue) do
    %{
      todo: Enum.count(queue.todo),
      pending: Enum.count(queue.pending),
      finished: Enum.count(queue.finished)
    }
  end

  @doc """
  Adds `task` to the queue's `todo` list, to be handed out by a later `pop/1`.
  """
  @spec enqueue(t(), task()) :: t()
  def enqueue(queue, task) do
    %{queue | todo: [task | queue.todo]}
  end

  @doc """
  Adds `tasks` to the queue's `todo` list, to be handed out by a later `pop/1`.
  """
  @spec enqueue_many(t(), [task()]) :: t()
  def enqueue_many(queue, tasks) do
    %{queue | todo: tasks ++ queue.todo}
  end

  @doc """
  Leases the next waiting item out of the queue.

  On success returns `{:ok, item, lease, queue}`: the item is moved from
  `todo` into `pending` under a fresh `lease` reference, which the caller
  passes back to `complete/2` when the work is done. Returns
  `{:error, :queue_empty}` when there is nothing waiting.
  """
  @spec pop(t()) :: {:ok, task(), lease(), t()} | {:error, :queue_empty}
  def pop(%{todo: []}) do
    {:error, :queue_empty}
  end

  def pop(%{todo: [item | items]} = queue) do
    pending_task = PendingTask.new(item)
    pending = Map.put(queue.pending, pending_task.lease, pending_task)
    queue = %{queue | todo: items, pending: pending}

    {:ok, item, pending_task.lease, queue}
  end

  @doc """
  Releases a leased item, marking its work done.

  Returns `{:ok, :completed, queue}` when `lease` was outstanding and has now
  been dropped from `pending`, or `{:ok, :ignored, queue}` when no such lease
  exists — because it was already completed, already swept, or never issued.
  Completing is therefore idempotent.
  """
  @spec complete(t(), lease()) :: {:ok, :completed | :ignored, t()}
  def complete(queue, lease) do
    if Map.has_key?(queue.pending, lease) do
      pending = Map.delete(queue.pending, lease)
      {:ok, :completed, %{queue | pending: pending}}
    else
      {:ok, :ignored, queue}
    end
  end

  @doc """
  Reclaims leases that have been outstanding longer than `max_age`.

  Each pending lease older than `max_age` is dropped and its item returned to
  `todo` to be handed out again; fresher leases are kept. `max_age` is a
  duration in the same native time units as `System.monotonic_time/0`.
  """
  @spec sweep(t(), integer()) :: t()
  def sweep(queue, max_age) do
    {kept, stale} =
      Enum.reduce(queue.pending, {%{}, []}, fn {lease, pending_task}, {kept, stale} ->
        if PendingTask.older_than?(pending_task, max_age) do
          {kept, [pending_task.item | stale]}
        else
          {Map.put(kept, lease, pending_task), stale}
        end
      end)

    %{queue | todo: queue.todo ++ stale, pending: kept}
  end
end
