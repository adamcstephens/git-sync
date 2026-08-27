defmodule GitSync.Connection do
  @moduledoc """
  A credential for one forge. At most one row per forge kind.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @kinds [:forgejo, :github, :tangled]

  @appview "https://tangled.org"

  schema "connections" do
    field :kind, Ecto.Enum, values: @kinds
    field :base_url, :string
    field :token, GitSync.Encrypted.Binary, redact: true
    field :refresh_token, GitSync.Encrypted.Binary, redact: true
    field :token_expires_at, :utc_datetime
    field :subject, :string
    field :ssh_key, GitSync.Encrypted.Binary, redact: true
    field :public_key, :string
    field :did, :string
    field :handle, :string
    field :pds_url, :string
    field :client_id, :string
    field :client_secret, GitSync.Encrypted.Binary, redact: true
    field :operator, :string

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [:kind, :base_url, :token])
    |> validate_required([:kind, :base_url])
    |> validate_change(:base_url, &validate_url/2)
    |> unique_constraint(:kind)
  end

  @doc """
  Changeset for a Tangled connection. The operator supplies the account and,
  at most, the appview to reach its knots through; the identity fields are
  resolved from the account rather than typed.
  """
  def tangled_changeset(connection, attrs) do
    base_url = attrs |> Map.get("base_url", "") |> String.trim() |> appview()

    connection
    |> changeset(Map.put(attrs, "base_url", base_url))
    |> cast(attrs, [:handle])
    |> validate_required([:handle])
  end

  defp appview(""), do: @appview
  defp appview(base_url), do: base_url

  @doc """
  Changeset for a forge whose credential is obtained over OAuth.
  """
  def oauth_changeset(connection, attrs) do
    connection
    |> changeset(attrs)
    |> cast(attrs, [:client_id, :client_secret])
    |> validate_required([:client_id, :client_secret])
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
