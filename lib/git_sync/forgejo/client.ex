defmodule GitSync.Forgejo.Client do
  @moduledoc """
  The slice of the Forgejo API git-sync needs: which repositories can be
  mirrored from or to.
  """

  alias GitSync.Connection

  @doc """
  Lists the repositories the connected operator can access.
  """
  def list_repos(%Connection{base_url: base_url, token: token}) do
    request =
      GitSync.Http.request(
        base_url: String.trim_trailing(base_url, "/"),
        url: "/api/v1/user/repos",
        params: [limit: 50],
        auth: {:bearer, token}
      )

    case Req.get(request) do
      {:ok, %Req.Response{status: 200, body: repos}} when is_list(repos) ->
        {:ok, Enum.map(repos, &repo/1)}

      {:ok, %Req.Response{status: status}} ->
        {:error, "Forgejo returned HTTP #{status}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  defp repo(%{"full_name" => full_name, "clone_url" => clone_url} = repo) do
    %{full_name: full_name, clone_url: clone_url, private: repo["private"]}
  end
end
