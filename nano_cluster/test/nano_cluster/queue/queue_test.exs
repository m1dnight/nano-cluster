defmodule NanoCluster.QueueTest do
  use ExUnit.Case, async: true

  alias NanoCluster.Queue

  describe "new/0" do
    test "starts empty" do
      queue = Queue.new()

      assert queue.todo == []
      assert queue.pending == %{}
      assert queue.jobs == %{}
      assert queue.finished == []
    end
  end

  describe "enqueue/2" do
    test "an enqueued item is waiting to be popped" do
      queue = Queue.new() |> Queue.enqueue(:work)

      assert {:ok, :work, _lease, _queue} = Queue.pop(queue)
    end
  end

  describe "pop/1" do
    test "an empty queue has nothing to pop" do
      assert Queue.pop(Queue.new()) == {:error, :queue_empty}
    end

    test "a popped item is removed from the todo list" do
      {:ok, :only, _lease, queue} = Queue.new() |> Queue.enqueue(:only) |> Queue.pop()

      assert queue.todo == []
      assert Queue.pop(queue) == {:error, :queue_empty}
    end

    test "the popped item comes back under a fresh reference lease" do
      {:ok, :work, lease, _queue} = Queue.new() |> Queue.enqueue(:work) |> Queue.pop()

      assert is_reference(lease)
    end

    test "each pop hands out its item under a distinct lease, draining the queue" do
      queue = Queue.new() |> Queue.enqueue(:a) |> Queue.enqueue(:b)

      {:ok, first, lease1, queue} = Queue.pop(queue)
      {:ok, second, lease2, queue} = Queue.pop(queue)

      assert lease1 != lease2
      assert Enum.sort([first, second]) == [:a, :b]
      assert Queue.pop(queue) == {:error, :queue_empty}
    end
  end

  describe "complete/2" do
    test "completing a held lease reports :completed and releases it from pending" do
      {:ok, :work, lease, queue} = Queue.new() |> Queue.enqueue(:work) |> Queue.pop()

      assert {:ok, :completed, queue} = Queue.complete(queue, lease)
      assert queue.pending == %{}
    end

    test "a completed item is never re-queued, even once its lease is stale" do
      {:ok, :work, lease, queue} = Queue.new() |> Queue.enqueue(:work) |> Queue.pop()

      {:ok, :completed, queue} = Queue.complete(queue, lease)
      # a negative max_age would re-queue any still-outstanding lease
      swept = Queue.sweep(queue, -1)

      assert swept.todo == []
      assert swept.pending == %{}
    end

    test "completing one lease leaves other outstanding leases untouched" do
      queue = Queue.new() |> Queue.enqueue(:a) |> Queue.enqueue(:b)
      {:ok, _first, lease1, queue} = Queue.pop(queue)
      {:ok, _second, lease2, queue} = Queue.pop(queue)

      {:ok, :completed, queue} = Queue.complete(queue, lease1)

      refute Map.has_key?(queue.pending, lease1)
      assert Map.has_key?(queue.pending, lease2)
    end

    test "completing an unknown lease reports :ignored and leaves the queue unchanged" do
      {:ok, :work, _lease, queue} = Queue.new() |> Queue.enqueue(:work) |> Queue.pop()

      assert {:ok, :ignored, ^queue} = Queue.complete(queue, make_ref())
    end

    test "completing the same lease twice reports :ignored the second time" do
      {:ok, :work, lease, queue} = Queue.new() |> Queue.enqueue(:work) |> Queue.pop()

      {:ok, :completed, queue} = Queue.complete(queue, lease)

      assert {:ok, :ignored, ^queue} = Queue.complete(queue, lease)
    end
  end

  describe "sweep/2" do
    test "a lease younger than max_age keeps holding its item" do
      one_hour = System.convert_time_unit(3600, :second, :native)
      {:ok, :work, lease, queue} = Queue.new() |> Queue.enqueue(:work) |> Queue.pop()

      swept = Queue.sweep(queue, one_hour)

      assert Map.has_key?(swept.pending, lease)
      assert swept.todo == []
    end

    test "a lease older than max_age is dropped and its item re-queued" do
      {:ok, :work, lease, queue} = Queue.new() |> Queue.enqueue(:work) |> Queue.pop()

      # a negative max_age makes every outstanding lease immediately stale
      swept = Queue.sweep(queue, -1)

      refute Map.has_key?(swept.pending, lease)
      assert swept.todo == [:work]
      assert {:ok, :work, _lease, _queue} = Queue.pop(swept)
    end

    test "sweeping a queue with no outstanding leases changes nothing" do
      queue = Queue.new() |> Queue.enqueue(:work)

      assert Queue.sweep(queue, 0) == queue
    end
  end
end
