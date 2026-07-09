defmodule NanoCluster.JobDescription.Primes do
  @moduledoc """
  A job that finds every prime in a range.

  The range is split into fixed-size chunks — one task per chunk — so the
  search can be spread across workers. Each task finds the primes in its
  chunk; the job's result is every prime in the range, in ascending order.
  """

  @typedoc "A `[start, stop]` sub-range to be searched for primes."
  @type args :: [integer()]

  @type t :: %__MODULE__{
          range: Range.t(),
          chunk_size: pos_integer()
        }

  @enforce_keys [:range]
  defstruct range: nil, chunk_size: 1000

  @doc """
  Builds a job that searches `range` for primes, `chunk_size` numbers per task.
  """
  @spec new(Range.t(), pos_integer()) :: t()
  def new(range, chunk_size \\ 1000) do
    %__MODULE__{range: range, chunk_size: chunk_size}
  end
end

defimpl NanoCluster.JobDescription, for: NanoCluster.JobDescription.Primes do
  alias NanoCluster.Task

  def tasks(%{range: range, chunk_size: size} = description) do
    range.first
    |> chunks(range.last, size)
    |> Enum.map(&Task.new(description, &1))
  end

  def run_task(_description, [start, stop]) do
    Enum.filter(start..stop, &prime?/1)
    |> Enum.count()
  end

  def combine_result(_description, left, right) do
    left + right
  end

  def empty_result(_description) do
    0
  end

  # Splits `start..last` into consecutive `[start, stop]` chunks of `size`.
  defp chunks(start, last, _size) when start > last, do: []

  defp chunks(start, last, size) do
    stop = min(start + size - 1, last)
    [[start, stop] | chunks(stop + 1, last, size)]
  end

  defp prime?(n) when n < 2, do: false
  defp prime?(2), do: true
  defp prime?(n) when rem(n, 2) == 0, do: false
  defp prime?(n), do: not has_factor?(n, 3)

  # True when `n` has an odd factor `>= i` (trial division, integer-only).
  defp has_factor?(n, i) when i * i > n, do: false
  defp has_factor?(n, i) when rem(n, i) == 0, do: true
  defp has_factor?(n, i), do: has_factor?(n, i + 2)
end
