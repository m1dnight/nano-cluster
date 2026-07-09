defmodule NanoCluster.NetworkTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias NanoCluster.Network

  # short timings so the tests don't wait out the real 10s sweep
  @opts [offline_threshold_ms: 50, sweep_interval_ms: 10]

  # On the host node() is :nonode@nohost, which sorts above nano@<ip> names
  # and below zeta@<ip> names.
  describe "liveness" do
    test "a peer is online when first heard from" do
      capture_io(fn ->
        {:ok, network} = Network.start_link(@opts)
        assert Network.statuses(network) == %{}

        send(network, {:discovered, :"nano@10.0.0.1"})
        assert Network.statuses(network) == %{:"nano@10.0.0.1" => :online}
      end)
    end

    test "the sweep marks a silent peer offline; it comes back when heard again" do
      capture_io(fn ->
        {:ok, network} = Network.start_link(@opts)
        send(network, {:discovered, :"nano@10.0.0.1"})

        Process.sleep(100)
        assert Network.statuses(network) == %{:"nano@10.0.0.1" => :offline}

        send(network, {:discovered, :"nano@10.0.0.1"})
        assert Network.statuses(network) == %{:"nano@10.0.0.1" => :online}
      end)
    end
  end

  describe "leader/1" do
    test "a lone node leads itself" do
      capture_io(fn ->
        {:ok, network} = Network.start_link(@opts)
        assert Network.leader(network) == node()
      end)
    end

    test "a lower peer coming online does not take the lead" do
      capture_io(fn ->
        {:ok, network} = Network.start_link(@opts)
        send(network, {:discovered, :"nano@10.0.0.1"})
        assert Network.leader(network) == node()
      end)
    end

    test "a higher peer coming online takes the lead" do
      capture_io(fn ->
        {:ok, network} = Network.start_link(@opts)
        send(network, {:discovered, :"zeta@10.0.0.9"})
        assert Network.leader(network) == :"zeta@10.0.0.9"
      end)
    end

    test "leadership falls back when the leader goes silent" do
      capture_io(fn ->
        {:ok, network} = Network.start_link(@opts)
        send(network, {:discovered, :"zeta@10.0.0.9"})
        assert Network.leader(network) == :"zeta@10.0.0.9"

        Process.sleep(100)
        assert Network.leader(network) == node()
      end)
    end
  end
end
