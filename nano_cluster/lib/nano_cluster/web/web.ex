defmodule NanoCluster.Web do
  @moduledoc """
  The node's HTTP server: a supervised `httpd` exposing the JSON API in
  `NanoCluster.Web.Api`.

  `httpd` (and its `gen_tcp_server`) are vendored under `src/` because they are
  not part of the flashed AtomVM stdlib - see the notes in those files. This
  module only owns starting one on the right port and pointing every `/api/*`
  request at the API handler.

  The API listens on port 8123 everywhere - boards and `just run-local`
  hosts alike (unprivileged, so no root is needed on a host). The overview
  page assumes this port for every node it fetches from.
  """

  # :httpd exists only on the AtomVM image; on the host it resolves to an
  # unrelated module, but this only runs under the VM.
  @compile {:no_warn_undefined, [:httpd]}

  alias NanoCluster.Web.Api

  @port 8123

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  @doc """
  Starts the HTTP server, linked to the caller, listening on all interfaces.

  Returns `{:ok, pid}` (the `httpd`/`gen_tcp_server` process) so it can be a
  supervised child, or `{:error, reason}` if the port cannot be bound.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(_opts \\ []) do
    :httpd.start_link(@port, config())
  end

  # One handler for everything under /api; Api dispatches on the path suffix.
  defp config do
    [{[<<"api">>], %{handler: Api, handler_config: %{}}}]
  end
end
