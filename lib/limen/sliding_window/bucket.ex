defmodule Limen.SlidingWindow.Bucket do
  @moduledoc false

  @typedoc """
  State of a single rate-limit bucket.

  * `window_start` — monotonic timestamp (ms) when the current window began
  * `current_count`  — request count in the current fixed window
  * `previous_count` — request count from the preceding fixed window
  """
  @type t :: %__MODULE__{
          window_start: integer(),
          current_count: non_neg_integer(),
          previous_count: non_neg_integer()
        }

  @enforce_keys [:window_start]
  defstruct [:window_start, current_count: 0, previous_count: 0]

  @spec new(window_start :: integer(), opts :: keyword()) :: t()
  def new(window_start, opts \\ []) do
    %__MODULE__{
      window_start: window_start,
      current_count: Keyword.get(opts, :current_count, 0),
      previous_count: Keyword.get(opts, :previous_count, 0)
    }
  end
end
