defmodule NanoClusterTest do
  use ExUnit.Case

  doctest NanoCluster.Distribution

  describe "Distribution.node_name/1" do
    test "formats the address as nano@<ip>" do
      assert NanoCluster.Distribution.node_name({192, 168, 4, 61}) == :"nano@192.168.4.61"
      assert NanoCluster.Distribution.node_name({10, 0, 0, 7}) == :"nano@10.0.0.7"
    end
  end
end
