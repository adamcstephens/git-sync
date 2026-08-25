defmodule GitSync.Forgejo.Client do
  @moduledoc """
  The slice of the Forgejo API git-sync needs: which repositories can be
  mirrored from or to, and how a repository tells us it has moved.
  """

  @behaviour GitSync.Forge

  alias GitSync.Connection
  alias GitSync.Forge.Webhook

  @signature_headers ["x-forgejo-signature", "x-gitea-signature"]

  @doc """
  Lists the repositories the connected operator can access.
  """
  @impl GitSync.Forge
  def list_repos(%Connection{token: token} = connection) do
    request =
      request(connection,
        url: "/api/v1/user/repos",
        params: [limit: 50],
        auth: {:bearer, token}
      )

    case Req.get(request) do
      {:ok, %Req.Response{status: 200, body: repos}} when is_list(repos) ->
        {:ok, Enum.map(repos, &repo/1)}

      other ->
        error(other)
    end
  end

  @impl GitSync.Forge
  def clone_url(%Connection{base_url: base_url}, repo, _mode),
    do: String.trim_trailing(base_url, "/") <> "/" <> repo

  @impl GitSync.Forge
  def create_webhook(%Connection{token: token} = connection, repo, url, secret) do
    request =
      request(connection,
        url: "/api/v1/repos/#{repo}/hooks",
        auth: {:bearer, token},
        json: %{
          type: "forgejo",
          active: true,
          events: ["push"],
          config: %{url: url, content_type: "json", secret: secret}
        }
      )

    case Req.post(request) do
      {:ok, %Req.Response{status: status, body: %{"id" => id}}} when status in 200..299 ->
        {:ok, id}

      other ->
        error(other)
    end
  end

  @impl GitSync.Forge
  def verify_webhook(%Connection{}, headers, body, secret),
    do: Webhook.verify_hmac_sha256(headers, body, secret, @signature_headers)

  defp request(%Connection{base_url: base_url}, options),
    do: GitSync.Http.request([base_url: String.trim_trailing(base_url, "/")] ++ options)

  defp error({:ok, %Req.Response{status: status}}),
    do: {:error, "Forgejo returned HTTP #{status}"}

  defp error({:error, exception}), do: {:error, Exception.message(exception)}

  defp repo(%{"full_name" => full_name, "clone_url" => clone_url} = repo) do
    %{full_name: full_name, clone_url: clone_url, private: repo["private"]}
  end
end
