defmodule SetNetworkConfig do
  @moduledoc """
  One-shot app that stores WiFi credentials in NVS under the `atomvm`
  namespace, where apps can read them back with
  `:esp.nvs_get_binary(:atomvm, :sta_ssid)` / `:sta_psk`.

  Credentials are baked in at compile time from the WIFI_SSID / WIFI_PSK
  environment variables, so they never live in source. Flash it with:

      just set-wifi <ssid> <psk> [port]

  then reflash the real app with `just flash-app`.
  """

  # :esp only exists on the AtomVM device image
  @compile {:no_warn_undefined, :esp}

  @ssid System.get_env("WIFI_SSID", "CHANGE_ME")
  @psk System.get_env("WIFI_PSK", "CHANGE_ME")

  @doc """
  Write the compiled-in credentials to NVS, echo them to the console
  (PSK redacted), and exit.
  """
  @spec start() :: :ok
  def start do
    :esp.nvs_put_binary(:atomvm, :sta_ssid, @ssid)
    :erlang.display({:atomvm, :sta_ssid, @ssid})
    :esp.nvs_put_binary(:atomvm, :sta_psk, @psk)
    :erlang.display({:atomvm, :sta_psk, "xxxxxx"})
    :ok
  end
end
