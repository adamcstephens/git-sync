defmodule GitSync.Knot do
  @moduledoc """
  The host keys pinned for one knot a connection pushes to.

  A Tangled account's repositories can be spread over several knots, and a
  host key belongs to the host rather than the account, so there is nowhere on
  the connection itself for one to live.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias GitSync.Connection

  schema "knots" do
    field :host, :string
    field :host_key, :string

    belongs_to :connection, Connection

    timestamps(type: :utc_datetime)
  end

  def changeset(knot, attrs) do
    knot
    |> cast(attrs, [:connection_id, :host, :host_key])
    |> validate_required([:connection_id, :host, :host_key])
    |> assoc_constraint(:connection)
    |> unique_constraint([:connection_id, :host])
  end
end
