defprotocol NanoCluster.JobDescription do
  @moduledoc """
  Describes how to turn a set of parameters into a job and its tasks.

  A job type provides a struct holding its parameters — a search range, an
  input document, whatever the work needs — and implements this protocol for
  that struct. The callbacks are the complete recipe for the job:

    * `tasks/1`          — split the description into a list of `NanoCluster.Task`s.
    * `run_task/2`       — run one task's `args`, producing its result.
    * `combine_result/3` — merge two task results into one.
    * `empty_result/1`   — the result of a job with no tasks (the identity for
                           `combine_result/3`).

  `NanoCluster.Job` assembles the final result by folding `combine_result/3`
  over the per-task results, starting from `empty_result/1`. Together those two
  form a monoid, and the fold is required to be well-defined, so an
  implementation must uphold two laws:

    * associativity — `combine_result/3` must not depend on how the results
      are grouped, only on their order.
    * identity — combining any result with `empty_result/1` returns it
      unchanged.

  Each task `tasks/1` produces carries the description and its own args, so a
  task can be shipped to any worker and run itself with
  `NanoCluster.Task.execute/1` — which dispatches back here through
  `run_task/2`. `NanoCluster.Job` drives the whole lifecycle; see its docs for
  an end-to-end example.

  An Elixir protocol dispatches on its first argument, so the description is
  the first argument of every callback — that is what lets one implementation
  own them all.
  """

  @typedoc "A job description: any struct implementing this protocol."
  @type t :: term()

  @typedoc "The arguments for one unit of work — carried by a task, run by `run_task/2`."
  @type args :: term()

  @doc """
  Splits the job `description` into a list of independently runnable
  `NanoCluster.Task`s.
  """
  @spec tasks(t()) :: [NanoCluster.Task.t()]
  def tasks(description)

  @doc """
  Runs one task's `args`, returning that task's result.
  """
  @spec run_task(t(), args()) :: term()
  def run_task(description, args)

  @doc """
  Combines two task results into one.

  `NanoCluster.Job` folds this over all of a job's task results to assemble the
  final result, so an implementation only needs to know how to merge a pair.
  Must be associative — see the module docs.
  """
  @spec combine_result(t(), term(), term()) :: term()
  def combine_result(description, left, right)

  @doc """
  Returns the result of a job with no tasks: the identity for `combine_result/3`.

  It seeds the fold in `NanoCluster.Job.result/1`, so combining it with any
  task result must return that result unchanged. For a job whose results are
  lists this is `[]`; for a sum it is `0`.
  """
  @spec empty_result(t()) :: term()
  def empty_result(description)
end
