defmodule GitSync.OidcProvider do
  @moduledoc """
  A minimal OpenID provider, enough for `oidcc` to complete a code flow against
  in tests. It signs ID tokens with a throwaway RSA key published at its own
  JWKS endpoint, and refuses a token request whose PKCE verifier does not match
  the challenge it saw on the authorization request.
  """

  use Plug.Router

  @state __MODULE__.State

  plug :match
  plug :fetch_query_params
  plug Plug.Parsers, parsers: [:urlencoded]
  plug :dispatch

  @doc """
  Starts the provider on a random port and returns its issuer URL.
  """
  def start(subject: subject, client_id: client_id) do
    {:ok, _agent} =
      Agent.start_link(
        fn ->
          %{jwk: JOSE.JWK.generate_key({:rsa, 2048}), subject: subject, client_id: client_id}
        end,
        name: @state
      )

    {:ok, server} = Bandit.start_link(plug: __MODULE__, port: 0, startup_log: false)
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    issuer = "http://127.0.0.1:#{port}"
    Agent.update(@state, &Map.put(&1, :issuer, issuer))

    issuer
  end

  @doc """
  The PKCE code challenge seen on the authorization request.
  """
  def code_challenge, do: Agent.get(@state, & &1[:code_challenge])

  @doc """
  The PKCE code verifier seen on the token request.
  """
  def code_verifier, do: Agent.get(@state, & &1[:code_verifier])

  get "/.well-known/openid-configuration" do
    issuer = get(:issuer)

    json(conn, %{
      issuer: issuer,
      authorization_endpoint: issuer <> "/authorize",
      token_endpoint: issuer <> "/token",
      userinfo_endpoint: issuer <> "/userinfo",
      jwks_uri: issuer <> "/jwks",
      scopes_supported: ~w(openid profile email),
      response_types_supported: ~w(code),
      subject_types_supported: ~w(public),
      id_token_signing_alg_values_supported: ~w(RS256),
      code_challenge_methods_supported: ~w(S256 plain)
    })
  end

  get "/jwks" do
    {_modules, public} = get(:jwk) |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()

    json(conn, %{keys: [Map.merge(public, %{"use" => "sig", "alg" => "RS256"})]})
  end

  get "/authorize" do
    %{"redirect_uri" => redirect_uri, "state" => state, "nonce" => nonce} = conn.query_params

    Agent.update(@state, fn provider ->
      provider
      |> Map.put(:nonce, nonce)
      |> Map.put(:code_challenge, conn.query_params["code_challenge"])
    end)

    conn
    |> put_resp_header("location", "#{redirect_uri}?code=the-code&state=#{URI.encode(state)}")
    |> send_resp(302, "")
  end

  post "/token" do
    verifier = conn.body_params["code_verifier"]
    Agent.update(@state, &Map.put(&1, :code_verifier, verifier))

    if verified_challenge?(verifier) do
      json(conn, %{
        access_token: "forgejo-access-token",
        token_type: "Bearer",
        id_token: id_token(),
        scope: "openid profile email"
      })
    else
      conn |> put_status(400) |> json(%{error: "invalid_grant"})
    end
  end

  get "/userinfo" do
    json(conn, %{sub: get(:subject), preferred_username: get(:subject)})
  end

  match _ do
    send_resp(conn, 404, "")
  end

  defp verified_challenge?(nil), do: false

  defp verified_challenge?(verifier) do
    challenge = Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

    challenge == code_challenge()
  end

  defp id_token do
    now = System.system_time(:second)

    claims = %{
      "iss" => get(:issuer),
      "sub" => get(:subject),
      "aud" => get(:client_id),
      "exp" => now + 300,
      "iat" => now,
      "nonce" => get(:nonce)
    }

    {_modules, token} =
      get(:jwk)
      |> JOSE.JWT.sign(%{"alg" => "RS256"}, claims)
      |> JOSE.JWS.compact()

    token
  end

  defp get(key), do: Agent.get(@state, &Map.fetch!(&1, key))

  defp json(conn, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(conn.status || 200, Jason.encode!(body))
  end
end
