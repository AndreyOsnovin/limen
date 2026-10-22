defmodule Limen.SlidingWindow do
  @moduledoc """
  Sliding Window Counter algorithm as described by [Cloudflare](https://blog.cloudflare.com/counting-things-a-lot-of-different-things).
  """

  alias Limen.SlidingWindow.Bucket

  @doc """
  Checks whether a request is within the rate limit.

  Returns `{:allow, updated_bucket}` if the request is allowed, or
  `{:deny, retry_after_ms}` where `retry_after_ms` is the number of
  milliseconds to wait before retrying.

  ## Examples

      iex> bucket = Limen.SlidingWindow.Bucket.new(0)
      iex> {:allow, bucket} = Limen.SlidingWindow.check(bucket, 10, 60_000, 0)
      iex> bucket
      %Limen.SlidingWindow.Bucket{current_count: 1, previous_count: 0, window_start: 0}

  """
  @spec check(Bucket.t(), pos_integer(), pos_integer(), integer()) ::
          {:allow, Bucket.t()} | {:deny, non_neg_integer()}
  def check(%Bucket{} = bucket, limit, window_ms, now_ms) do
    if expired?(bucket, window_ms, now_ms) do
      {:allow, Bucket.new(now_ms, current_count: 1)}
    else
      do_check(bucket, limit, window_ms, now_ms - bucket.window_start)
    end
  end

  @doc """
  Returns `true` when the bucket's window ended over a full window ago, so its
  counts no longer carry any weight and the bucket can be dropped.
  """
  @spec expired?(Bucket.t(), pos_integer(), integer()) :: boolean()
  def expired?(%Bucket{window_start: window_start}, window_ms, now_ms) do
    now_ms - window_start >= 2 * window_ms
  end

  defp do_check(%Bucket{} = bucket, limit, window_ms, elapsed) when elapsed >= window_ms do
    rolled = Bucket.new(bucket.window_start + window_ms, previous_count: bucket.current_count)
    do_check(rolled, limit, window_ms, elapsed - window_ms)
  end

  defp do_check(%Bucket{} = bucket, limit, window_ms, elapsed) do
    # estimate = previous_count * (1 - elapsed / window_ms) + current_count + 1
    # Both sides of `estimate <= limit` are multiplied by `window_ms` to stay in integers:
    # with floats, `30 * (1 - 42_000 / 60_000)` is 9.000000000000002 and denies an allowed request.
    scaled_previous = bucket.previous_count * (window_ms - elapsed)
    scaled_estimate = scaled_previous + (bucket.current_count + 1) * window_ms

    if scaled_estimate <= limit * window_ms do
      {:allow, %{bucket | current_count: bucket.current_count + 1}}
    else
      previous_allowed = limit - 1 - bucket.current_count

      retry_ms =
        if previous_allowed >= 0 do
          retry_after(bucket.previous_count, previous_allowed, elapsed, window_ms)
        else
          # The current window alone is over the limit: wait for it to end and fade
          # as the previous window. Its fade starts at `window_ms`, hence the shift.
          retry_after(bucket.current_count, limit - 1, elapsed - window_ms, window_ms)
        end

      {:deny, retry_ms}
    end
  end

  # Milliseconds until `fading_count * (1 - t / window_ms) <= allowed`, where `t` is
  # the time since the fading window ended and `elapsed` is the current `t`.
  # Rounded up, so a retry after exactly this many milliseconds succeeds.
  defp retry_after(fading_count, allowed, elapsed, window_ms) do
    t = div(window_ms * (fading_count - allowed) + fading_count - 1, fading_count)
    max(t - elapsed, 0)
  end
end
