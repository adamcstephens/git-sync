defmodule GitSync.Mapping do
  @moduledoc """
  One source repository mirrored onto one destination repository. A source with
  several destinations is several rows.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias GitSync.Connection
  alias GitSync.Run

  schema "mappings" do
    field :source_repo, :string
    field :destination_repo, :string
    field :interval_seconds, :integer, default: 3600
    field :enabled, :boolean, default: true

    belongs_to :source_connection, Connection
    belongs_to :destination_connection, Connection
    has_many :runs, Run

    timestamps(type: :utc_datetime)
  end

  def changeset(mapping, attrs) do
    mapping
    |> cast(attrs, [
      :source_connection_id,
      :source_repo,
      :destination_connection_id,
      :destination_repo,
      :interval_seconds,
      :enabled
    ])
    |> validate_required([
      :source_connection_id,
      :source_repo,
      :destination_connection_id,
      :destination_repo
    ])
    |> validate_number(:interval_seconds, greater_than_or_equal_to: 60)
    |> assoc_constraint(:source_connection)
    |> assoc_constraint(:destination_connection)
    |> unique_constraint([:destination_connection_id, :destination_repo])
  end
end
