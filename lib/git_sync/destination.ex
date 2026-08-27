defmodule GitSync.Destination do
  @moduledoc """
  One replica of a source: the forge to push to and the repository there.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias GitSync.Connection
  alias GitSync.RepoName
  alias GitSync.Source

  schema "destinations" do
    field :repo, :string
    field :enabled, :boolean, default: true

    belongs_to :source, Source
    belongs_to :connection, Connection

    timestamps(type: :utc_datetime)
  end

  @doc """
  The half of a destination the form asks for. A destination added alongside a
  new source has no source to point at yet.
  """
  def form_changeset(destination, attrs) do
    destination
    |> cast(attrs, [:connection_id, :repo, :enabled])
    |> validate_required([:connection_id, :repo])
    |> RepoName.validate(:repo)
  end

  def changeset(destination, attrs) do
    destination
    |> form_changeset(attrs)
    |> cast(attrs, [:source_id])
    |> validate_required([:source_id])
    |> assoc_constraint(:source)
    |> assoc_constraint(:connection)
    |> unique_constraint([:connection_id, :repo])
  end
end
