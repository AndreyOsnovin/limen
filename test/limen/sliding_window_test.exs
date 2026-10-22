defmodule Limen.SlidingWindowTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Limen.SlidingWindow
  alias Limen.SlidingWindow.Bucket

  doctest Limen.SlidingWindow

  @limit 10
  @window :timer.seconds(60)

  describe "check/4 — within current window" do
    test "(increments current count on each allowed request)" do
      bucket = Bucket.new(0)

      Enum.reduce(1..@limit, bucket, fn expected_count, acc ->
        {:allow, updated} = SlidingWindow.check(acc, @limit, @window, 0)
        assert updated.current_count == expected_count
        updated
      end)
    end

    test "(rejects the request that exceeds the limit)" do
      bucket = Bucket.new(0, current_count: @limit)
      assert {:deny, _} = SlidingWindow.check(bucket, @limit, @window, 0)
    end

    test "(retry_after decreases as elapsed approaches window_ms)" do
      bucket = Bucket.new(0, current_count: @limit)

      {:deny, retry_after_early} = SlidingWindow.check(bucket, @limit, @window, 1_000)
      {:deny, retry_after_late} = SlidingWindow.check(bucket, @limit, @window, 30_000)

      assert retry_after_early > retry_after_late
    end

    test "(previous window weight fades as elapsed approaches window_ms)" do
      # previous_count=10 at elapsed=0 would block, but at elapsed=59_000 its weight is ~0.016
      # so estimate = 10 * 0.016 + 0 + 1 ≈ 1.16 — well within limit
      bucket = Bucket.new(0, previous_count: @limit)
      assert {:allow, _} = SlidingWindow.check(bucket, @limit, @window, 59_000)
    end

    test "(previous window still has significant weight near window start)" do
      # at elapsed=1_000: weight = 1 - 1/60 ≈ 0.983
      # estimate = 10 * 0.983 + 0 + 1 ≈ 10.83 > 10
      bucket = Bucket.new(0, previous_count: @limit)
      assert {:deny, _} = SlidingWindow.check(bucket, @limit, @window, 1_000)
    end
  end

  describe "check/4 — window boundary crossed" do
    test "(promotes current to previous and opens a new window)" do
      bucket = Bucket.new(0, current_count: 5)
      now = @window + 1

      assert {:allow, new_bucket} = SlidingWindow.check(bucket, @limit, @window, now)
      assert new_bucket.previous_count == 5
      assert new_bucket.current_count == 1
      assert new_bucket.window_start == @window
    end

    test "(allows request when weighted estimate is within limit)" do
      # elapsed=70_000, weight = 1 - 10/60 ≈ 0.833
      # estimate = 8 * 0.833 + 1 ≈ 7.66 <= 10
      bucket = Bucket.new(0, current_count: 8)
      assert {:allow, _} = SlidingWindow.check(bucket, @limit, @window, 70_000)
    end

    test "(rejects request when previous window tail exceeds limit)" do
      # elapsed=61_000, weight = 1 - 1/60 ≈ 0.983
      # estimate = 10 * 0.983 + 1 ≈ 10.83 > 10
      bucket = Bucket.new(0, current_count: @limit)
      assert {:deny, _} = SlidingWindow.check(bucket, @limit, @window, 61_000)
    end
  end

  describe "check/4 — retry_after" do
    test "(full current window waits for the boundary plus the fade of current_count)" do
      # at 60_000 current becomes previous: 10 * (1 - o/60_000) + 1 <= 10 needs o >= 6_000
      bucket = Bucket.new(0, current_count: @limit)
      assert {:deny, 66_000} = SlidingWindow.check(bucket, @limit, @window, 0)
    end

    test "(is the exact moment the next request is allowed)" do
      buckets =
        for current <- 0..@limit, previous <- [0, 1, 5, @limit, 3 * @limit] do
          Bucket.new(0, current_count: current, previous_count: previous)
        end

      for bucket <- buckets, now <- [0, 1_000, 30_000, 59_999, 60_000, 90_000] do
        with {:deny, retry_ms} <- SlidingWindow.check(bucket, @limit, @window, now) do
          assert {:allow, _} = SlidingWindow.check(bucket, @limit, @window, now + retry_ms)
          assert {:deny, _} = SlidingWindow.check(bucket, @limit, @window, now + retry_ms - 1)
        end
      end
    end
  end

  describe "check/4 — both windows expired" do
    test "(resets state and allows the request)" do
      bucket = Bucket.new(0, current_count: @limit)
      now = @window * 2 + 1

      assert {:allow, new_bucket} = SlidingWindow.check(bucket, @limit, @window, now)
      assert new_bucket.previous_count == 0
      assert new_bucket.current_count == 1
      assert new_bucket.window_start == now
    end
  end
end
