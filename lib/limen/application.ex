defmodule Limen.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {PartitionSupervisor,
       child_spec: Limen.Server,
       name: Limen.Server.Partitions,
       partitions: Application.get_env(:limen, :partitions, 1)}
    ]

    opts = [strategy: :one_for_one, name: Limen.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
