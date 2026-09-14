defmodule GitSync.Pushin.Client do
  @moduledoc """
  Pushin.eu repository access using a personal access token. API requests go to
  pushin.eu; HTTPS Git transfers use the separate git.pushin.eu host.
  """

  @behaviour GitSync.Forge

  alias GitSync.Connection
  alias GitSync.Forge.Pages

  @impl GitSync.Forge
  def list_repos(%Connection{token: token}) when token in [nil, ""],
    do: {:error, "Connect Pushin.eu to list its repositories"}

  def list_repos(%Connection{} = connection) do
    fetch = fn page, per_page ->
      request =
        request(
          url: "/api/v1/user/repos",
          params: [page: page, per_page: per_page],
          auth: {:bearer, connection.token}
        )

      case Req.get(request) do
        {:ok, %Req.Response{status: 200, body: repos}} when is_list(repos) -> {:ok, repos}
        other -> error(other)
      end
    end

    case Pages.collect(fetch) do
      {:ok, repos} -> {:ok, repos |> Enum.reject(& &1["archived"]) |> Enum.map(&repo/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl GitSync.Forge
  def check(%Connection{token: token}) when token in [nil, ""],
    do: {:error, "Connect Pushin.eu to check the account"}

  def check(%Connection{} = connection) do
    request = request(url: "/api/v1/user", auth: {:bearer, connection.token})

    case Req.get(request) do
      {:ok, %Req.Response{status: 200}} -> :ok
      other -> error(other)
    end
  end

  @impl GitSync.Forge
  def clone_url(%Connection{}, repo, _mode), do: "https://git.pushin.eu/#{repo}.git"

  @impl GitSync.Forge
  def create_webhook(%Connection{}, _repo, _url, _secret), do: {:error, :unsupported}

  @impl GitSync.Forge
  def verify_webhook(%Connection{}, _headers, _body, _secret), do: {:error, :unsupported}

  @impl GitSync.Forge
  def refresh(%Connection{}), do: {:error, :unsupported}

  defp request(options), do: GitSync.Http.request([base_url: "https://pushin.eu"] ++ options)

  defp error({:ok, %Req.Response{status: status}}),
    do: {:error, "Pushin.eu returned HTTP #{status}"}

  defp error({:error, exception}), do: {:error, Exception.message(exception)}

  defp repo(%{"full_name" => full_name, "clone_url" => clone_url} = repo) do
    %{full_name: full_name, clone_url: clone_url, private: repo["private"]}
  end
end
