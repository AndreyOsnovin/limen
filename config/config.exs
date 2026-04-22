import Config

config :limen,
  partitions: System.schedulers_online(),
  prune_interval: :timer.minutes(5)
