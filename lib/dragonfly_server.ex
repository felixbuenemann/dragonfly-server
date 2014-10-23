defmodule DragonflyServer do
  use Application

  def job_cache_table_name, do: :job_cache
  def http_engine_cache_table_name, do: :http_engine_cache

  def start(_type, _args) do
    Plug.Adapters.Cowboy.http WebServer, [], port: System.get_env("PORT") |> String.to_integer,
                                             acceptors: Application.get_env(:web_server, :acceptors),
                                             compress: true
    start_workers
    start_caches
  end

  defp start_workers do
    import Supervisor.Spec, warn: false

    worker_pool_options = [
      name: {:local, :dragonfly_worker_pool},
      worker_module: JobWorker,
      size: Application.get_env(:process_worker_pool, :size),
      max_overflow: Application.get_env(:process_worker_pool, :max_overflow)
    ]

    children = [
      :poolboy.child_spec(:dragonfly_worker_pool, worker_pool_options, []),
    ]

    opts = [strategy: :one_for_one, name: DragonflyServer.WorkerSupervisor]
    Supervisor.start_link(children, opts)
  end

  defp start_caches do
    import Supervisor.Spec, warn: false

    :ets.new(job_cache_table_name, [:named_table, :public, {:read_concurrency, true}])
    :ets.new(http_engine_cache_table_name, [:named_table, :public, {:read_concurrency, true}])

    children = [
      worker(JobCacheStore, []),
      worker(HttpEngine, [])
    ]

    opts = [strategy: :one_for_one,
            max_restarts: 10,
            max_seconds: 1,
            name: DragonflyServer.CacheSupervisor]
    Supervisor.start_link(children, opts)
  end
end
