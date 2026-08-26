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
  def clone_url(%Connection{base_url: base_url}, repo, :read) do
    {_host, path} = split(repo)

    String.trim_trailing(base_url, "/") <> "/" <> path
  end

  def clone_url(%Connection{base_url: base_url} = connection, repo, :write) do
    {_host, path} = split(repo)

    "git@" <> (knot_host(connection, repo) || URI.parse(base_url).host) <> ":" <> path
  end

  @doc """
  The knot a repo lives on when it names one, and `nil` when it lives on the
  connection's own. The appview proxies git over HTTP for every knot, so this
  only ever changes where a push goes.
  """
  def knot_host(%Connection{}, repo) do
    {host, _path} = split(repo)

    host
  end

  defp split(repo) do
    case String.split(repo, "/") do
      [host, owner, name] -> {host, owner <> "/" <> name}
      _ -> {nil, repo}
    end
  end

  @impl GitSync.Forge
  def create_webhook(%Connection{}, _repo, _url, _secret), do: {:error, :unsupported}

  @impl GitSync.Forge
  def verify_webhook(%Connection{}, _headers, _body, _secret), do: {:error, :unsupported}

  @impl GitSync.Forge
  def refresh(%Connection{}), do: {:error, :unsupported}
end
