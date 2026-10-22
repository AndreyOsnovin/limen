defmodule Limen.Server do
  @moduledoc false

  use GenServer

  alias Limen.SlidingWindow
  alias Limen.SlidingWindow.Bucket

  @doc """
  Starts the server.

  ## Options

  * `:prune_interval` — how often expired buckets are removed, in milliseconds.
    Required.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Checks whether `key` is within the rate limit.

  Returns `:ok` if the request is allowed, or `{:error, retry_after_ms}` where
  `retry_after_ms` is the number of milliseconds to wait before retrying.
  """
  @spec check(GenServer.server(), term(), pos_integer(), pos_integer()) ::
          :ok | {:error, non_neg_integer()}
  def check(server, key, limit, window_ms) do
    GenServer.call(server, {:check, key, limit, window_ms})
  end

  @doc """
  Resets the counters for `key` across all windows.
  """
  @spec reset(GenServer.server(), term()) :: :ok
  def reset(server, key) do
    GenServer.call(server, {:reset, key})
  end

  # Buckets are stored as `%{key => %{window_ms => bucket}}`, so several limits
  # with different windows on the same key do not reset each other.
  @impl true
  def init(opts) do
    prune_interval = Keyword.fetch!(opts, :prune_interval)
    schedule_next_prune(prune_interval)
    {:ok, %{buckets: %{}, prune_interval: prune_interval}}
  end

  @impl true
  def handle_call({:check, key, limit, window_ms}, _from, %{buckets: buckets} = state) do
    now_ms = System.monotonic_time(:millisecond)
    windows = Map.get(buckets, key, %{})
    bucket = Map.get_lazy(windows, window_ms, fn -> Bucket.new(now_ms) end)

    case SlidingWindow.check(bucket, limit, window_ms, now_ms) do
      {:allow, updated_bucket} ->
        windows = Map.put(windows, window_ms, updated_bucket)
        {:reply, :ok, %{state | buckets: Map.put(buckets, key, windows)}}

      {:deny, retry_after_ms} ->
        {:reply, {:error, retry_after_ms}, state}
    end
  end

  @impl true
  def handle_call({:reset, key}, _from, %{buckets: buckets} = state) do
    {:reply, :ok, %{state | buckets: Map.delete(buckets, key)}}
  end

  # shortcut: prune blocks the partition (~1s per 1M keys in it); raise `:partitions`,
  # or move buckets to ETS and run `select_delete` in a separate process.
  @impl true
  def handle_info(:prune, %{buckets: buckets, prune_interval: prune_interval} = state) do
    now_ms = System.monotonic_time(:millisecond)

    buckets =
      for {key, windows} <- buckets,
          windows =
            Map.reject(windows, fn {window_ms, bucket} ->
              SlidingWindow.expired?(bucket, window_ms, now_ms)
            end),
          windows != %{},
          into: %{},
          do: {key, windows}

    schedule_next_prune(prune_interval)

    {:noreply, %{state | buckets: buckets}}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule_next_prune(interval) do
    Process.send_after(self(), :prune, interval)
  end
end
