# Limen

Rate limiting based on the
[Sliding Window Counter](https://blog.cloudflare.com/counting-things-a-lot-of-different-things/) algorithm.

Rate limit state is stored in memory and is not shared across nodes.

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
  :ok ->
    # proceed
  {:error, retry_after_ms} ->
    # retry after retry_after_ms ms
end
```

To reset the counter for a key (e.g. after a successful login):

```elixir
Limen.reset({:login, user_id})
```
