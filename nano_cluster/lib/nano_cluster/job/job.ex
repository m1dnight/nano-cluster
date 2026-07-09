defmodule NanoCluster.Job do
  @moduledoc """
  A job is a `NanoCluster.JobDescription` in progress: the tasks it was split
  into, and the results reported back so far.

  A job holds everything needed to tell whether the work is finished and, once
  it is, to assemble the final result:

    * `id` — a unique reference identifying this job, generated at
      construction. Every task is stamped with it (as `job_id`) so a completed
      task can be routed back to its job.
    * `description` — the `NanoCluster.JobDescription` the job was built from;
      kept so `result/1` can ask it to combine the task results.
    * `tasks` — the ordered list of `NanoCluster.Task`s, produced by the
      description. Fixed at construction; this is the plan of work.
    * `results` — the results reported back so far, keyed by task `id`. A
      task's `id` appears here exactly once its work has been completed.

  Results are keyed by task `id` rather than kept as a parallel list so that
  `put_complete/2` is idempotent and `complete?/1` is a plain presence check.

  A job is a plain data structure: it holds no processes and does no work of
  its own.

  ## Example

      description = NanoCluster.JobDescription.Primes.new(2..30, 10)
      job = NanoCluster.Job.from_description(description)

      # Each task can run itself, wherever it lives:
      job =
        Enum.reduce(job.tasks, job, fn task, job ->
          NanoCluster.Job.put_complete(job, NanoCluster.Task.execute(task))
        end)

      NanoCluster.Job.result(job)
      #=> {:ok, [2, 3, 5, 7, 11, 13, 17, 19, 23, 29]}
  """

  alias NanoCluster.Job
  alias NanoCluster.JobDescription
  alias NanoCluster.Task

  @typedoc "Unique identity of a job, generated at construction."
  @type id :: reference()

  @type t :: %__MODULE__{
          id: id(),
          description: JobDescription.t(),
          tasks: [Task.t()],
          results: %{Task.id() => term()}
        }

  defstruct id: nil, description: nil, tasks: [], results: %{}

  @doc """
  Builds a job from a `NanoCluster.JobDescription`.

  Generates a fresh job `id`, asks the description for its `tasks/1`, and
  stamps each task with the job id so completed tasks can be routed home.
  """
  @spec from_description(JobDescription.t()) :: t()
  def from_description(description) do
    id = make_ref()
    tasks = description |> JobDescription.tasks() |> Enum.map(&Task.assign(&1, id))
    %Job{id: id, description: description, tasks: tasks}
  end

  @doc """
  Records a completed `task`, storing its result under the task's `id`.

  Reporting the same task more than once simply overwrites the earlier
  result, so completing is idempotent.
  """
  @spec put_complete(t(), Task.t()) :: t()
  def put_complete(job, task) do
    # remove some data from the struct we no longer need

    %{job | results: Map.put(job.results, task.id, task.result)}
  end

  @doc """
  Returns `true` once every one of the job's `tasks` has reported a result.
  """
  @spec complete?(t()) :: boolean()
  def complete?(job) do
    Enum.all?(job.tasks, fn task -> Map.has_key?(job.results, task.id) end)
  end

  @doc """
  Assembles the job's final result once it is complete.

  Returns `{:ok, result}` — the task results folded together with the
  description's `combine_result/3`, starting from its `empty_result/1` — when
  every task has reported back, or `{:error, :incomplete}` while any task is
  still outstanding. A job with no tasks is complete, and its result is the
  description's `empty_result/1`.
  """
  @spec result(t()) :: {:ok, term()} | {:error, :incomplete}
  def result(job) do
    if complete?(job) do
      result =
        job.tasks
        |> Enum.reduce(JobDescription.empty_result(job.description), fn task, acc ->
          JobDescription.combine_result(job.description, acc, job.results[task.id])
        end)

      {:ok, result}
    else
      {:error, :incomplete}
    end
  end
end
