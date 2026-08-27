defmodule GitSync.Run do
  @moduledoc """
  One tick of a source: the fetch it did, and a `GitSync.RunTarget` for each
  destination it pushed to.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias GitSync.RunTarget
  alias GitSync.Source

  @statuses [:running, :success, :failure]

  schema "runs" do
    field :status, Ecto.Enum, values: @statuses, default: :running
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :log, :string

    belongs_to :source, Source
    has_many :targets, RunTarget

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:source_id, :status, :started_at, :finished_at, :log])
    |> validate_required([:source_id, :status, :started_at])
    |> assoc_constraint(:source)
  end
end
