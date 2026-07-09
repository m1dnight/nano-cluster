defmodule MyLogger do
  @moduledoc """
  Simple placeholder module for the Logger module.
  """

  @level :info
  @levels [:debug, :info, :warning, :error]

  @spec info(String.t()) :: :ok
  def info(message) do
    log(:info, message)
  end

  @spec debug(String.t()) :: :ok
  def debug(message) do
    log(:debug, message)
  end

  @spec error(String.t()) :: :ok
  def error(message) do
    log(:error, message)
  end

  @spec warning(String.t()) :: :ok
  def warning(message) do
    log(:warning, message)
  end

  @spec log(atom(), String.t()) :: :ok
  defp log(level, message) do
    levels = levels()

    if level in levels do
      time = System.monotonic_time(:second)
      IO.puts("#{time} #{inspect(level)} :: #{message}")
    end

    :ok
  end

  defp levels(levels \\ @levels)

  defp levels([]), do: []

  defp levels([level | levels]) when level == @level do
    [level | levels]
  end

  defp levels([_ | levels]) do
    levels(levels)
  end
end
