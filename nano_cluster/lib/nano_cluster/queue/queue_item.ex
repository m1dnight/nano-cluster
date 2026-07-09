defmodule NanoCluster.Queue.PendingTask do
  @moduledoc """
  A single work item that has been leased out of the queue and is
  awaiting completion.

  Built with `new/1`, which stamps the item with a fresh `lease`
  reference and the monotonic time at which it was leased.
  """

  @type lease :: reference()
  @type task :: term()
  @type timestamp :: integer()

  @type t :: %__MODULE__{
          timestamp: timestamp(),
          item: task(),
          lease: lease()
        }

  defstruct timestamp: nil, item: nil, lease: nil

  @doc """
  Wraps `work_item` in a pending task carrying a fresh lease reference
  and a monotonic lease timestamp.
  """
  @spec new(task()) :: t()
  def new(work_item) do
    %__MODULE__{lease: make_ref(), timestamp: System.monotonic_time(), item: work_item}
  end

  @doc """
  Returns `true` when the task has been pending longer than `max_age`.

  `max_age` is a duration expressed in the same native time units as
  `System.monotonic_time/0`.
  """
  @spec older_than?(t(), integer()) :: boolean()
  def older_than?(pending_task, max_age) do
    System.monotonic_time() - pending_task.timestamp > max_age
  end
end
