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
    elapsed = now_ms - bucket.window_start
    do_check(bucket, limit, window_ms, elapsed, now_ms)
  end

  # Both windows have expired — reset and allow.
  defp do_check(_bucket, _limit, window_ms, elapsed, now_ms) when elapsed >= 2 * window_ms do
    {:allow, Bucket.new(now_ms, current_count: 1)}
  end

  # Window boundary crossed — promote `current_count` to `previous_count` and open a new window.
  defp do_check(%Bucket{} = bucket, limit, window_ms, elapsed, _now_ms)
       when elapsed >= window_ms do
    window_offset = elapsed - window_ms
    weight = 1 - window_offset / window_ms
    estimated_count = bucket.current_count * weight + 1

    if estimated_count <= limit do
      bucket =
        Bucket.new(bucket.window_start + window_ms,
          previous_count: bucket.current_count,
          current_count: 1
        )

      {:allow, bucket}
    else
      retry_ms = retry_after(bucket.current_count, limit - 1, window_offset, window_ms)
      {:deny, retry_ms}
    end
  end

  # Within the current window — previous_count fades linearly as elapsed approaches window_ms.
  defp do_check(%Bucket{} = bucket, limit, window_ms, elapsed, _now_ms) do
    weight = 1 - elapsed / window_ms
    estimated_count = bucket.previous_count * weight + bucket.current_count + 1

    if estimated_count <= limit do
      {:allow, %{bucket | current_count: bucket.current_count + 1}}
    else
      remaining = limit - 1 - bucket.current_count
      retry_ms = retry_after(bucket.previous_count, remaining, elapsed, window_ms)
      {:deny, retry_ms}
    end
  end

  defp retry_after(0, _remaining, elapsed, window_ms), do: window_ms - elapsed

  defp retry_after(previous_count, remaining, elapsed, window_ms) do
    max(round(window_ms * (1 - remaining / previous_count) - elapsed), 0)
  end
end
