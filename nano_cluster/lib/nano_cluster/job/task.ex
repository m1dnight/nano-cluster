defmodule NanoCluster.Task do
  @moduledoc """
  A task is a subset of a job: one independently executable unit of work.

  A task is self-contained: it carries the `NanoCluster.JobDescription` it was
  produced from and the `args` describing its slice of the work, so it can be
  handed to any worker and run there with `execute/1` — no other context
  needed. It also carries a unique `id`, so its result can be matched back into
  the job, and the `job_id` of the job it belongs to (assigned by
  `NanoCluster.Job.from_description/1`) so a completed task can be routed home.

  A freshly built task has a `nil` result; `execute/1` runs the work and fills
  it in.
  """

  alias NanoCluster.JobDescription

  @typedoc "Unique identity of a task within its job."
  @type id :: reference()

  @type t :: %__MODULE__{
          id: id(),
          job_id: reference() | nil,
          description: JobDescription.t(),
          args: JobDescription.args(),
          result: term()
        }

  @enforce_keys [:id, :description]
  defstruct id: nil, job_id: nil, description: nil, args: nil, result: nil

  @doc """
  Builds a task that runs `args` against `description`, with a fresh `id`.
  """
  @spec new(JobDescription.t(), JobDescription.args()) :: t()
  def new(description, args) do
    %__MODULE__{id: make_ref(), description: description, args: args}
  end

  @doc """
  Ties `task` to the job identified by `job_id`.
  """
  @spec assign(t(), reference()) :: t()
  def assign(task, job_id) do
    %{task | job_id: job_id}
  end

  @doc """
  Runs the task and returns it with its `result` filled in.

  The work is dispatched through `NanoCluster.JobDescription.run_task/2` using
  the description and args the task carries — this is how a task runs itself,
  wherever it happens to live.
  """
  @spec execute(t()) :: t()
  def execute(task) do
    complete(task, JobDescription.run_task(task.description, task.args))
  end

  @doc """
  Records `result` on `task` without running it.
  """
  @spec complete(t(), term()) :: t()
  def complete(task, result) do
    %{task | result: result}
  end
end
