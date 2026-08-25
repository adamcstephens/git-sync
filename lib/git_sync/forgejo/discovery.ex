defmodule GitSync.Forgejo.Discovery do
  @moduledoc """
  OpenID Connect discovery against a Forgejo instance.

  The wizard runs this before saving anything, so an operator finds out about a
  typo'd URL on the form rather than halfway through their first login.
  """

  @required ~w(issuer authorization_endpoint token_endpoint userinfo_endpoint)

  @doc """
  Fetches the discovery document and confirms it describes a usable provider.
  """
  def fetch(base_url) do
    url = String.trim_trailing(base_url, "/") <> "/.well-known/openid-configuration"

    case Req.get(GitSync.Http.request(url: url)) do
      {:ok, %Req.Response{status: 200, body: %{} = body}} -> validate(body)
      {:ok, %Req.Response{status: status}} -> {:error, "discovery returned HTTP #{status}"}
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end

  defp validate(body) do
    case Enum.reject(@required, &is_binary(body[&1])) do
      [] -> {:ok, body}
      missing -> {:error, "discovery document is missing #{Enum.join(missing, ", ")}"}
    end
  end
end
