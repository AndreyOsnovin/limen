defmodule Limen.ServerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Limen.Server

  @limit 10
  @window :timer.seconds(60)

  setup do
    server = start_supervised!({Server, prune_interval: :timer.minutes(1)})
    {:ok, server: server}
  end

  describe "check/4" do
    test "(returns {:error, retry_after_ms} when limit is exceeded)", %{server: server} do
      Enum.each(1..@limit, fn _ -> assert :ok = Server.check(server, "key", @limit, @window) end)
      assert {:error, retry_after_ms} = Server.check(server, "key", @limit, @window)
      assert retry_after_ms > 0
    end

    test "(exhausting one key does not affect another)", %{server: server} do
      Enum.each(1..@limit, fn _ -> assert :ok = Server.check(server, "a", @limit, @window) end)
      assert {:error, _} = Server.check(server, "a", @limit, @window)
      assert :ok = Server.check(server, "b", @limit, @window)
    end
  end

  describe "check/4 — window_ms change" do
    test "(changing window_ms discards the old bucket)", %{server: server} do
      Enum.each(1..@limit, fn _ -> Server.check(server, "key", @limit, @window) end)
      assert {:error, _} = Server.check(server, "key", @limit, @window)
      assert :ok = Server.check(server, "key", @limit, @window * 2)
    end
  end

  describe "prune" do
    test "(bucket is gone after :prune message)", %{server: server} do
      Server.check(server, "key", @limit, 1)
      Process.sleep(10)
      send(server, :prune)
      %{table: table} = :sys.get_state(server)
      assert :ets.lookup(table, "key") == []
    end
  end

  describe "reset/2" do
    test "(allows requests again after reset)", %{server: server} do
      Enum.each(1..@limit, fn _ -> assert :ok = Server.check(server, "key", @limit, @window) end)
      assert {:error, _} = Server.check(server, "key", @limit, @window)
      assert :ok = Server.reset(server, "key")
      assert :ok = Server.check(server, "key", @limit, @window)
    end

    test "(resetting one key does not affect another)", %{server: server} do
      Enum.each(1..@limit, fn _ -> assert :ok = Server.check(server, "a", @limit, @window) end)
      Enum.each(1..@limit, fn _ -> assert :ok = Server.check(server, "b", @limit, @window) end)
      Server.reset(server, "a")
      assert {:error, _} = Server.check(server, "b", @limit, @window)
      assert :ok = Server.check(server, "a", @limit, @window)
    end

    test "(reset on unknown key returns :ok)", %{server: server} do
      assert :ok = Server.reset(server, "unknown")
    end
  end

  describe "concurrency" do
    test "(allowed count never exceeds limit under concurrent load)", %{server: server} do
      results =
        1..50
        |> Task.async_stream(
          fn _ -> Server.check(server, "key", @limit, @window) end,
          max_concurrency: 50
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.count(results, &(&1 == :ok)) == @limit
    end
  end
end
