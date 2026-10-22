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

  describe "check/4 — several windows on one key" do
    test "(each window_ms is tracked independently)", %{server: server} do
      Enum.each(1..@limit, fn _ -> Server.check(server, "key", @limit, @window) end)
      assert {:error, _} = Server.check(server, "key", @limit, @window)
      assert :ok = Server.check(server, "key", @limit, @window * 2)
      assert {:error, _} = Server.check(server, "key", @limit, @window)
    end

    test "(alternating windows still enforce the limit)", %{server: server} do
      results =
        for _ <- 1..@limit, window <- [@window, @window * 2] do
          Server.check(server, "key", @limit, window)
        end

      assert Enum.all?(results, &(&1 == :ok))
      assert {:error, _} = Server.check(server, "key", @limit, @window)
      assert {:error, _} = Server.check(server, "key", @limit, @window * 2)
    end
  end

  describe "prune" do
    test "(removes expired buckets and keeps live ones)", %{server: server} do
      Server.check(server, "expired", @limit, 1)
      Server.check(server, "live", @limit, @window)
      Process.sleep(10)
      send(server, :prune)
      %{buckets: buckets} = :sys.get_state(server)
      assert Map.keys(buckets) == ["live"]
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

    test "(reset clears all windows of the key)", %{server: server} do
      for window <- [@window, @window * 2], _ <- 1..@limit do
        Server.check(server, "key", @limit, window)
      end

      Server.reset(server, "key")
      assert :ok = Server.check(server, "key", @limit, @window)
      assert :ok = Server.check(server, "key", @limit, @window * 2)
    end
  end
end
