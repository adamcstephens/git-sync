defmodule GitSync.RepoName do
  @moduledoc """
  The shape a repository name takes at either end of a mirror.
  """

  import Ecto.Changeset

  @format ~r{\A([^\s/]+/)?[^\s/]+/[^\s/]+\z}
  @message "must look like owner/name, optionally prefixed with a knot host"

  def message, do: @message

  def validate(changeset, field),
    do: validate_format(changeset, field, @format, message: @message)
end
