defmodule GitSync.Connection do
  @moduledoc """
  A credential for one forge. At most one row per forge kind.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @kinds [:forgejo, :github, :tangled]

  schema "connections" do
    field :kind, Ecto.Enum, values: @kinds
    field :base_url, :string
    field :token, GitSync.Encrypted.Binary, redact: true
    field :ssh_key, GitSync.Encrypted.Binary, redact: true

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [:kind, :base_url, :token, :ssh_key])
    |> validate_required([:kind, :base_url])
    |> validate_change(:base_url, &validate_url/2)
    |> unique_constraint(:kind)
  end

  defp validate_url(field, value) do
    case URI.new(value) do
      {:ok, %URI{scheme: scheme, host: host}}
      when scheme in ["http", "https"] and host not in [nil, ""] ->
        []

      _ ->
        [{field, "must be an http or https URL"}]
    end
  end
end
