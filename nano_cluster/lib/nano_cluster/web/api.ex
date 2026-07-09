defmodule NanoCluster.Web.Api do
  @moduledoc """
  The `httpd` handler behind every node's JSON API.

  `httpd` calls `init_handler/2` then `handle_http_req/2` for each request, both
  in its single server process, so a handler must not block for long: the reads
  here are fast local `GenServer` calls, and the one cross-node hop (submitting a
  job to the leader, in `NanoCluster.JobQueue.submit/1`) uses a bounded wait.

  Routes (all under the `[<<"api">>]` prefix `NanoCluster.Web` registers, so the
  request's `path_suffix` is what is left after `api`):

    * `GET  /api/network`     - this node's cluster view
    * `GET  /api/work/queue`  - this node's queue occupancy
    * `GET  /api/work/jobs`   - this node's jobs, running and done
    * `GET  /api/work/items`  - the catalog of submittable job types
    * `POST /api/work`        - submit a job to the leader

  Every response carries `Access-Control-Allow-Origin: *` so the overview page,
  opened from a laptop, can read a board's replies, and is returned with the
  `{:close, headers, body}` form so the socket closes after it - the browser sees
  the response terminate even though `httpd` sets no chunked encoding.
  """

  # :json is in the AtomVM stdlib (and OTP 27+ on the host); it is never linked
  # into the plain-Elixir build the editor/dialyzer see.
  @compile {:no_warn_undefined, :json}

  alias NanoCluster.Job
  alias NanoCluster.JobQueue
  alias NanoCluster.Network
  alias NanoCluster.Web.Catalog
  alias NanoCluster.JobDescription.Primes

  # ---------------------------------------------------------------------------#
  #                            httpd handler callbacks                         #
  # ---------------------------------------------------------------------------#

  @doc false
  def init_handler(_path_suffix, config) do
    {:ok, config}
  end

  @doc false
  def handle_http_req(request, _handler_state) do
    route(request.method, request.path_suffix, request)
  end

  # ---------------------------------------------------------------------------#
  #                                  Routes                                    #
  # ---------------------------------------------------------------------------#

  defp route(:get, [<<"network">>], _request) do
    json(Network.view())
  end

  defp route(:get, [<<"work">>, <<"queue">>], _request) do
    json(JobQueue.queue_stats())
  end

  defp route(:get, [<<"work">>, <<"jobs">>], _request) do
    results =
      Enum.map(JobQueue.job_results(), fn completed ->
        result = case completed.result do
          {:ok, result} ->
            result
          _ ->
            "failed"
          end
        %{completed | job_id: inspect(completed.job_id), result: result}
      end)

    json(%{jobs: results})
  end

  defp route(:post, [<<"work">>], request) do
    submit_work(request.body)
  end

  # A cross-origin JSON POST is preceded by a CORS preflight. httpd parses the
  # OPTIONS method as :undefined (it only knows GET/PUT/POST/DELETE); answering
  # any such request under /api with the allow headers lets the POST through.
  defp route(:undefined, _path_suffix, _request) do
    {:close, cors(preflight_headers()), ""}
  end

  defp route(_method, _path_suffix, _request) do
    {:error, :not_found}
  end

  # ---------------------------------------------------------------------------#
  #                              POST /api/work                                #
  # ---------------------------------------------------------------------------#

  defp submit_work(body) do
    with {:ok, %{"job" => work_item, "arguments" => arguments}} <- decode(body),
         job when not is_nil(job) <- decode_job(work_item, arguments) do
      JobQueue.add_job(job)
      json(%{job: inspect(job.id)})
    else
      _ ->
        {:error, :bad_request}
    end
  end

  defp decode(body) do
    {:ok, :json.decode(body)}
  rescue
    _ -> {:error, :bad_json}
  end

  defp decode_job(work_item, arguments) do
    case String.to_atom(work_item) do
      Primes ->
        %{"start" => from, "end" => to, "chunk_size" => cs} = arguments
        primes = Primes.new(from..to, cs)
        Job.from_description(primes)

      _ ->
        nil
    end
  end

  # ---------------------------------------------------------------------------#
  #                                 Responses                                  #
  # ---------------------------------------------------------------------------#

  # `data` is encoded with :json, which turns atoms into strings - so node names,
  # :online/:offline and :running/:done all serialise cleanly. Use the atom
  # :null (not nil, which would encode as the string "nil") for a JSON null.
  defp json(data) do
    body = :erlang.iolist_to_binary(:json.encode(data))
    {:close, cors(json_headers(body)), body}
  end

  defp json_headers(body) do
    %{
      "Content-Type" => "application/json",
      "Content-Length" => Integer.to_string(byte_size(body))
    }
  end

  defp preflight_headers do
    %{
      "Allow" => "GET, POST, OPTIONS",
      "Access-Control-Allow-Methods" => "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers" => "Content-Type",
      "Content-Length" => "0"
    }
  end

  defp cors(headers) do
    Map.put(headers, "Access-Control-Allow-Origin", "*")
  end
end
