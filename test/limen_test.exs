defmodule LimenTest do
  @moduledoc false

  # Limen registers global names, so tests cannot run concurrently.
  use ExUnit.Case, async: false

  setup do
    start_supervised!({Limen, partitions: 2})
    :ok
  end

  test "(check and reset are routed to the same partition)" do
    Enum.each(1..3, fn _ -> assert :ok = Limen.check({:login, 1}, 3, :timer.minutes(1)) end)
    assert {:error, _} = Limen.check({:login, 1}, 3, :timer.minutes(1))
    assert :ok = Limen.reset({:login, 1})
    assert :ok = Limen.check({:login, 1}, 3, :timer.minutes(1))
  end

  test "(rejects invalid limit and window_ms)" do
    for {limit, window_ms} <- [{"10", 1_000}, {nil, 1_000}, {0, 1_000}, {10, 0}, {10, 1.5}] do
      assert_raise FunctionClauseError, fn -> Limen.check(:key, limit, window_ms) end
    end
  end
end
