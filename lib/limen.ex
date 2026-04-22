defmodule Limen do
  @moduledoc """
  Rate limiting based on the
  [Sliding Window Counter](https://blog.cloudflare.com/counting-things-a-lot-of-different-things)
  algorithm.

  Rate limit state is stored in memory and is not shared across nodes.

  ## Usage

  Call `check/3` before processing a request. Pass any term as the key — a user
  ID, IP address, API token, or a tuple combining several of these:

  ```elixir
  case Limen.check({:login, user_id}, 5, :timer.minutes(1)) do
    :ok ->
      # within limit — proceed
    {:error, retry_after_ms} ->
      # limit exceeded — retry after retry_after_ms ms
  end
  ```

  To reset the counter for a key (e.g. after a successful login):

  ```elixir
  Limen.reset({:login, user_id})
  ```

  ## Configuration

  ```elixir
  config :limen,
    # Number of worker processes. Increase to reduce contention under high
    # concurrency. Defaults to the number of schedulers online.
    partitions: System.schedulers_online(),

    # How often expired buckets are removed from memory. Defaults to 5 minutes.
    prune_interval: :timer.minutes(5)
  ```
  """

  alias Limen.Server

  @doc """
  Checks whether `key` is within the rate limit.
  """
  @spec check(key :: term(), limit :: pos_integer(), window_ms :: pos_integer()) ::
          :ok | {:error, retry_after_ms :: non_neg_integer()}
  def check(key, limit, window_ms) do
    via = {:via, PartitionSupervisor, {Limen.Server.Partitions, key}}
    Server.check(via, key, limit, window_ms)
  end

  @doc """
  Resets the counter for `key`.
  """
  @spec reset(key :: term()) :: :ok
  def reset(key) do
    via = {:via, PartitionSupervisor, {Limen.Server.Partitions, key}}
    Server.reset(via, key)
  end
end
