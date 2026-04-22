defmodule Limen.Server do
  @moduledoc false

  use GenServer

  alias Limen.SlidingWindow
  alias Limen.SlidingWindow.Bucket

  @default_prune_interval :timer.minutes(5)

  @doc """
  Starts the server.

  ## Options

  * `:prune_interval` — how often expired buckets are removed, in milliseconds.
    Defaults to `5` minutes.
  """
  @spec start_link(opts :: keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Checks whether `key` is within the rate limit.
  """
  @spec check(
          server :: GenServer.server(),
          key :: term(),
          limit :: pos_integer(),
          window_ms :: pos_integer()
        ) ::
          :ok | {:error, retry_after_ms :: non_neg_integer()}
  def check(server, key, limit, window_ms) do
    GenServer.call(server, {:check, key, limit, window_ms})
  end

  @doc """
  Resets the counter for `key`.
  """
  @spec reset(server :: GenServer.server(), key :: term()) :: :ok
  def reset(server, key) do
    GenServer.call(server, {:reset, key})
  end

  @impl true
  def init(opts) do
    table = :ets.new(:buckets, [:set, :public])
    prune_interval = Keyword.get(opts, :prune_interval, @default_prune_interval)
    schedule_next_prune(prune_interval)
    {:ok, %{table: table, prune_interval: prune_interval}}
  end

  @impl true
  def handle_call({:check, key, limit, window_ms}, _from, %{table: table} = state) do
    now_ms = System.monotonic_time(:millisecond)
    bucket = upsert_bucket(table, key, window_ms, now_ms)

    case SlidingWindow.check(bucket, limit, window_ms, now_ms) do
      {:allow, updated_bucket} ->
        :ets.insert(table, {key, updated_bucket, window_ms})
        {:reply, :ok, state}

      {:deny, retry_after_ms} ->
        {:reply, {:error, retry_after_ms}, state}
    end
  end

  @impl true
  def handle_call({:reset, key}, _from, %{table: table} = state) do
    :ets.delete(table, key)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:prune, %{table: table, prune_interval: prune_interval} = state) do
    Task.start(fn ->
      now_ms = System.monotonic_time(:millisecond)

      :ets.select_delete(table, [
        {{:_, %Bucket{window_start: :"$1", current_count: :_, previous_count: :_}, :"$2"},
         [{:>=, {:-, now_ms, :"$1"}, {:*, 2, :"$2"}}], [true]}
      ])
    end)

    schedule_next_prune(prune_interval)

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule_next_prune(interval) do
    Process.send_after(self(), :prune, interval)
  end

  # If `window_ms` changed for an existing key, the old bucket is discarded and a new window starts.
  defp upsert_bucket(table, key, window_ms, now_ms) do
    case :ets.lookup(table, key) do
      [{_, bucket, ^window_ms}] -> bucket
      _ -> Bucket.new(now_ms)
    end
  end
end
