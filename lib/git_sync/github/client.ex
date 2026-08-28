defmodule GitSync.Github.Client do
  @moduledoc """
  The slice of the GitHub API git-sync needs: which repositories can be mirrored
  from or to, and how a repository tells us it has moved.
  """

  @behaviour GitSync.Forge

  alias GitSync.Connection
  alias GitSync.Forge.Pages
  alias GitSync.Forge.Webhook

  @api_url "https://api.github.com"
  @signature_headers ["x-hub-signature-256"]

  @doc """
  Lists the repositories the stored token can reach.
  """
  @impl GitSync.Forge
  def list_repos(%Connection{token: nil}),
    do: {:error, "Connect GitHub to list its repositories"}

  def list_repos(%Connection{token: token}) do
    fetch = fn page, per_page ->
      request =
        request(
          url: "/user/repos",
          params: [page: page, per_page: per_page, sort: "full_name"],
          auth: {:bearer, token}
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
  def clone_url(%Connection{base_url: base_url}, repo, _mode),
    do: String.trim_trailing(base_url, "/") <> "/" <> repo

  @impl GitSync.Forge
  def create_webhook(%Connection{token: token}, repo, url, secret) do
    request =
      request(
        url: "/repos/#{repo}/hooks",
        auth: {:bearer, token},
        json: %{
          name: "web",
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
  defdelegate refresh(connection), to: GitSync.Github.OAuth

  @impl GitSync.Forge
  def verify_webhook(%Connection{}, headers, body, secret),
    do: Webhook.verify_hmac_sha256(headers, body, secret, @signature_headers, "sha256=")

  defp request(options), do: GitSync.Http.request([base_url: @api_url] ++ options)

  defp error({:ok, %Req.Response{status: status}}), do: {:error, "GitHub returned HTTP #{status}"}
  defp error({:error, exception}), do: {:error, Exception.message(exception)}

  defp repo(%{"full_name" => full_name, "clone_url" => clone_url} = repo) do
    %{full_name: full_name, clone_url: clone_url, private: repo["private"]}
  end
end
