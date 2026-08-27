defmodule GitSync.RunTarget do
  @moduledoc """
  What one destination made of a run's fetch.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias GitSync.Destination
  alias GitSync.Run

  @statuses [:success, :failure]

  schema "run_targets" do
    field :status, Ecto.Enum, values: @statuses
    field :refs_pushed, {:array, :string}, default: []
    field :log, :string

    belongs_to :run, Run
    belongs_to :destination, Destination

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(target, attrs) do
    target
    |> cast(attrs, [:run_id, :destination_id, :status, :refs_pushed, :log])
    |> validate_required([:run_id, :destination_id, :status])
    |> assoc_constraint(:run)
    |> assoc_constraint(:destination)
  end
end
