defmodule GitSync.Github.Client do
  @moduledoc """
  The slice of the GitHub API git-sync needs: which repositories can be mirrored
  from or to.
  """

  alias GitSync.Connection

  @api_url "https://api.github.com"

  @doc """
  Lists the repositories the stored token can reach.
  """
  def list_repos(%Connection{token: token}) do
    request =
      GitSync.Http.request(
        base_url: @api_url,
        url: "/user/repos",
        params: [per_page: 50, sort: "full_name"],
        auth: {:bearer, token}
      )

    case Req.get(request) do
      {:ok, %Req.Response{status: 200, body: repos}} when is_list(repos) ->
        {:ok, Enum.map(repos, &repo/1)}

      {:ok, %Req.Response{status: status}} ->
        {:error, "GitHub returned HTTP #{status}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  defp repo(%{"full_name" => full_name, "clone_url" => clone_url} = repo) do
    %{full_name: full_name, clone_url: clone_url, private: repo["private"]}
  end
end
