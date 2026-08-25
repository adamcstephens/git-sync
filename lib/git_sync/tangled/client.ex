defmodule GitSync.Tangled.Client do
  @moduledoc """
  Tangled knots speak plain git and nothing else: no repository listing and no
  webhooks, so a Tangled mapping is driven entirely by its timer.
  """

  @behaviour GitSync.Forge

  alias GitSync.Connection

  @impl GitSync.Forge
  def list_repos(%Connection{}), do: {:error, :unsupported}

  @impl GitSync.Forge
  def clone_url(%Connection{base_url: base_url}, repo, :read),
    do: String.trim_trailing(base_url, "/") <> "/" <> repo

  def clone_url(%Connection{base_url: base_url}, repo, :write),
    do: "git@" <> URI.parse(base_url).host <> ":" <> repo

  @impl GitSync.Forge
  def create_webhook(%Connection{}, _repo, _url, _secret), do: {:error, :unsupported}

  @impl GitSync.Forge
  def verify_webhook(%Connection{}, _headers, _body, _secret), do: {:error, :unsupported}
end
