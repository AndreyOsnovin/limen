defmodule Limen do
  @moduledoc """
  Rate limiting based on the
  [Sliding Window Counter](https://blog.cloudflare.com/counting-things-a-lot-of-different-things)
  algorithm.

  Rate limit state is stored in memory and is not shared across nodes. If a
  partition process crashes, the counters it held are lost.

  ## Setup

  Add `Limen` to your supervision tree:

  ```elixir
  children = [
    {Limen, partitions: 4, prune_interval: :timer.minutes(5)}
  ]
  ```

  Or rely on defaults (`partitions` = schedulers online, `prune_interval` = 5 minutes):

  ```elixir
  children = [Limen]
  ```

  ## Usage

  ```elixir
  case Limen.check({:login, user_id}, 5, :timer.minutes(1)) do
    :ok -> # proceed
    {:error, retry_after_ms} -> # retry after retry_after_ms ms
  end

  Limen.reset({:login, user_id})
  ```
  """

  alias Limen.Server

  @default_prune_interval :timer.minutes(5)

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc """
  Starts Limen as part of a supervision tree.

  ## Options

  * `:partitions` — number of worker processes. Defaults to `System.schedulers_online()`.
    Pruning briefly blocks a partition (about 1 second per million keys in it),
    so raise this for many keys, e.g. `64`.
  * `:prune_interval` — how often expired buckets are removed, in milliseconds.
    Defaults to `5` minutes.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    partitions = Keyword.get(opts, :partitions, System.schedulers_online())
    prune_interval = Keyword.get(opts, :prune_interval, @default_prune_interval)

    children = [
      {PartitionSupervisor,
       child_spec: {Server, prune_interval: prune_interval},
       name: Limen.Partitions,
       partitions: partitions}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Limen.Supervisor)
  end

  @doc """
  Checks whether `key` is within the rate limit.

  Returns `:ok` if the request is allowed, or `{:error, retry_after_ms}` where
  `retry_after_ms` is the number of milliseconds to wait before retrying.

  The same `key` may be checked against several windows (e.g. 10 per minute and
  100 per hour); each `window_ms` is tracked independently.

  Raises `FunctionClauseError` unless `limit` and `window_ms` are positive integers.
  """
  @spec check(term(), pos_integer(), pos_integer()) :: :ok | {:error, non_neg_integer()}
  def check(key, limit, window_ms)
      when is_integer(limit) and limit > 0 and is_integer(window_ms) and window_ms > 0 do
    via = {:via, PartitionSupervisor, {Limen.Partitions, key}}
    Server.check(via, key, limit, window_ms)
  end

  @doc """
  Resets the counters for `key` across all windows.
  """
  @spec reset(term()) :: :ok
  def reset(key) do
    via = {:via, PartitionSupervisor, {Limen.Partitions, key}}
    Server.reset(via, key)
  end
end
