defmodule NanoCluster.Queue.PendingTaskTest do
  use ExUnit.Case, async: true

  alias NanoCluster.Queue.PendingTask

  describe "new/1" do
    test "builds a PendingTask carrying the work item verbatim" do
      item = %{job: :render, args: [1, 2, 3]}

      assert %PendingTask{item: ^item} = PendingTask.new(item)
    end

    test "hands the task a reference lease" do
      assert %PendingTask{lease: lease} = PendingTask.new(:work)
      assert is_reference(lease)
    end

    test "each task gets its own distinct lease" do
      %PendingTask{lease: first} = PendingTask.new(:work)
      %PendingTask{lease: second} = PendingTask.new(:work)

      assert first != second
    end

    test "stamps the task with a monotonic integer timestamp" do
      before = System.monotonic_time()
      %PendingTask{timestamp: timestamp} = PendingTask.new(:work)
      later = System.monotonic_time()

      assert is_integer(timestamp)
      assert timestamp >= before
      assert timestamp <= later
    end

    test "a task leased later never carries an earlier timestamp" do
      %PendingTask{timestamp: first} = PendingTask.new(:first)
      %PendingTask{timestamp: second} = PendingTask.new(:second)

      assert second >= first
    end

    test "any term is a valid work item" do
      for item <- [:atom, 42, "string", {:tuple, 1}, %{map: true}, [1, 2, 3], self()] do
        assert %PendingTask{item: ^item} = PendingTask.new(item)
      end
    end
  end

  describe "older_than?/2" do
    test "a task leased longer ago than max_age is old" do
      one_second = System.convert_time_unit(1, :second, :native)

      task = %PendingTask{
        lease: make_ref(),
        item: :work,
        timestamp: System.monotonic_time() - 10 * one_second
      }

      assert PendingTask.older_than?(task, one_second)
    end

    test "a freshly leased task is not older than a generous max_age" do
      one_hour = System.convert_time_unit(3600, :second, :native)

      refute PendingTask.older_than?(PendingTask.new(:work), one_hour)
    end
  end
end
