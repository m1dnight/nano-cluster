alias NanoCluster.Discovery
alias NanoCluster.Distribution
alias NanoCluster.Job
alias NanoCluster.JobDescription
alias NanoCluster.JobDescription.Primes
alias NanoCluster.JobQueue
alias NanoCluster.JobQueue.Worker
alias NanoCluster.Network
alias NanoCluster.Task
alias NanoCluster.Wifi
js = JobDescription.Primes.new(1..500, 100)
j = Job.from_description(js)
{:ok, jobqueue} = JobQueue.start_link()

JobQueue.add_job(j)

execute_task = fn ->
  case JobQueue.take_task() do
    {:ok, task, lease} ->
      IO.puts("Got task")
      task = Task.execute(task) |> tap(&IO.inspect(&1, label: ""))
      JobQueue.put_task_result(task, lease)
      :ok

    _ ->
      IO.puts("No tasks")
      :ok
  end
end
