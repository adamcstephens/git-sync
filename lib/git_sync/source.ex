defmodule GitSync.Source do
  @moduledoc """
  A repository to mirror, and the terms it is mirrored on: how often, and the
  webhook the forge calls when it moves. Where it lands is its destinations.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias GitSync.Connection
  alias GitSync.Destination
  alias GitSync.RepoName
  alias GitSync.Run

  schema "sources" do
    field :repo, :string
    field :interval_seconds, :integer, default: 3600
    field :enabled, :boolean, default: true
    field :webhook_secret, GitSync.Encrypted.Binary, redact: true
    field :webhook_id, :string

    belongs_to :connection, Connection
    has_many :destinations, Destination
    has_many :runs, Run

    timestamps(type: :utc_datetime)
  end

  def changeset(source, attrs) do
    source
    |> cast(attrs, [:connection_id, :repo, :interval_seconds, :enabled])
    |> validate_required([:connection_id, :repo])
    |> RepoName.validate(:repo)
    |> validate_number(:interval_seconds, greater_than_or_equal_to: 60)
    |> assoc_constraint(:connection)
    |> unique_constraint([:connection_id, :repo])
  end
end
