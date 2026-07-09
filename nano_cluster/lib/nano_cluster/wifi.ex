defmodule NanoCluster.Wifi do
  @moduledoc """
  WiFi in station mode, using credentials stored in NVS by SetNetworkConfig
  (`just set-wifi <ssid> <psk>`).
  """

  # :esp, :network and :atomvm only exist on the AtomVM image
  @compile {:no_warn_undefined, [:esp, :network, :atomvm]}

  @retry_delay_ms 2000

  @doc """
  Connect with the credentials in NVS, retrying until it succeeds.

  Returns `{:ok, address}` once the board has associated and obtained an IP
  via DHCP, or `:no_credentials` when NVS holds none. Transient failures
  (bad reception, AP hiccups) are retried forever, so `{:ok, _}` is the only
  successful outcome - but with a wrong password this blocks indefinitely.

  On generic_unix (a `just run-local` dev run) there is no WiFi driver;
  the host is already networked, so this returns loopback immediately.
  """
  @spec connect() :: {:ok, NanoCluster.ip_address()} | :no_credentials
  def connect do
    case :atomvm.platform() do
      :generic_unix ->
        IO.puts("generic_unix: no WiFi driver, using loopback")
        {:ok, {192, 168, 4, 180}}

      _device ->
        connect_sta()
    end
  end

  @spec connect_sta() :: {:ok, NanoCluster.ip_address()} | :no_credentials
  defp connect_sta do
    case :esp.nvs_get_binary(:atomvm, :sta_ssid) do
      :undefined ->
        :no_credentials

      ssid ->
        psk = :esp.nvs_get_binary(:atomvm, :sta_psk)
        {:ok, connect(ssid, psk)}
    end
  end

  # Block until association + DHCP succeed; tear the driver down and retry
  # on any failure (wait_for_sta gives up after 30s on its own).
  @spec connect(binary(), binary() | :undefined) :: NanoCluster.ip_address()
  defp connect(ssid, psk) do
    IO.puts("Connecting to WiFi...")

    case :network.wait_for_sta([ssid: ssid, psk: psk], 30_000) do
      {:ok, {address, _netmask, _gateway}} ->
        :io.format(~c"Connected with IP ~p~n", [address])
        address

      error ->
        :io.format(~c"WiFi connect failed (~p), retrying in 2s~n", [error])
        :network.stop()
        :timer.sleep(@retry_delay_ms)
        connect(ssid, psk)
    end
  end
end
