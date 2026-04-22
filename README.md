# Limen

Rate limiting based on the
[Sliding Window Counter](https://blog.cloudflare.com/counting-things-a-lot-of-different-things/) algorithm.

Rate limit state is stored in memory and is not shared across nodes.

## Usage

Call `Limen.check/3` before processing a request. Pass any term as the key — a user
ID, IP address, API token, or a tuple combining several of these:

```elixir
case Limen.check({:login, user_id}, 5, :timer.minutes(1)) do
  :ok ->
    # within limit — proceed
  {:error, retry_after_ms} ->
    # limit exceeded — ask the client to retry after retry_after_ms milliseconds
end
```

To clear the counter for a key (e.g. after a successful password reset):

```elixir
Limen.reset({:login, user_id})
```

## Configuration

```elixir
config :limen,
  # Number of worker processes. Increase to reduce contention under high
  # concurrency. Defaults to the number of schedulers online.
  partitions: System.schedulers_online(),

  # How often expired counters are removed from memory. Defaults to 5 minutes.
  prune_interval: :timer.minutes(5)
```
