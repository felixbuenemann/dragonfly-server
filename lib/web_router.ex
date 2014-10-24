defmodule WebRouter do
  import Plug.Conn
  use Plug.Router

  @max_age 31536000 # 1 year

  # Plug order matters, as they are inserted as middlewares
  plug Plug.Logger
  plug Plug.Head
  plug :match
  plug :dispatch
  plug Plug.Cache

  delete "/admin/media/:payload" do
    :ok = expire_image(payload)
    send_resp(conn, 202, "Scheduled deletion")
  end

  get "/media/:payload/:filename" do
    {format, response} = case JobCacheStore.get(payload) do
      nil -> compute_image(payload)
      match -> match
    end
    conn
    |> add_headers(format, filename)
    |> resp(200, response)
  end

  match _ do
    resp(conn, 404, "Image not found")
  end

  defp compute_image(payload) do
    :poolboy.transaction(:dragonfly_worker_pool, fn(worker) ->
      JobWorker.process(worker, payload)
    end)
  end

  def expire_image(payload) do
    :poolboy.transaction(:dragonfly_worker_pool, fn(worker) ->
      JobWorker.expire(worker, payload)
    end)
  end

  defp add_headers(conn, format, filename) do
    conn
    |> put_resp_header("Content-Type", header_for_format(format))
    |> put_resp_header("cache-control", "public, max-age=#{@max_age}")
    |> put_resp_header("Content-Disposition", "filename=\"#{filename}\"")
  end

  defp header_for_format("jpg"), do: "image/jpg"
  defp header_for_format("png"), do: "image/png"
end
