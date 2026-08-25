defmodule GitSync.Forge.Token do
  @moduledoc """
  A credential as a forge hands it out: the access token, the refresh token
  that renews it, the moment it stops working, and — where the forge names one
  — the subject it was issued to.
  """

  defstruct [:access, :refresh, :expires_at, :subject]

  @type t :: %__MODULE__{
          access: String.t(),
          refresh: String.t() | nil,
          expires_at: DateTime.t() | nil,
          subject: String.t() | nil
        }

  @margin_seconds 60

  @doc """
  Builds a token from the lifetime in seconds both forges report.
  """
  def new(access, refresh, expires_in) do
    %__MODULE__{access: access, refresh: refresh, expires_at: expires_at(expires_in)}
  end

  @doc """
  Whether the access token is close enough to expiry to be worth renewing.
  """
  def spent?(%__MODULE__{expires_at: nil}), do: false

  def spent?(%__MODULE__{expires_at: expires_at}),
    do: DateTime.diff(expires_at, DateTime.utc_now()) <= @margin_seconds

  defp expires_at(nil), do: nil

  defp expires_at(seconds) when is_integer(seconds),
    do: DateTime.utc_now() |> DateTime.add(seconds, :second) |> DateTime.truncate(:second)
end
