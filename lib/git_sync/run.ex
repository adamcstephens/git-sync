defmodule GitSync.Run do
  @moduledoc """
  The outcome of a single sync attempt for one mapping.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses [:running, :success, :failure]

  schema "runs" do
    field :status, Ecto.Enum, values: @statuses, default: :running
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :refs_pushed, {:array, :string}, default: []
    field :log, :string

    belongs_to :mapping, GitSync.Mapping

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:mapping_id, :status, :started_at, :finished_at, :refs_pushed, :log])
    |> validate_required([:mapping_id, :status, :started_at])
    |> assoc_constraint(:mapping)
  end
end
