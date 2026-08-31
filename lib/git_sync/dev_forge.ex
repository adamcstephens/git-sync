if Application.compile_env(:git_sync, :dev_routes) do
  defmodule GitSync.DevForge do
    @moduledoc """
    Answers every outbound HTTP request a development instance makes, so the
    pages that are driven by a forge's API render without a forge anywhere near
    them. `config/dev.exs` installs it as the plug `GitSync.Http` builds each
    request against, which is also what stops a dev instance reaching the real
    Forgejo, GitHub or atproto hosts it is configured with.

    What it holds is what `GitSync.DevSeeds` seeded, and the only credential it
    accepts is `GitSync.DevSeeds.token/0`.

    This module is compiled out of any build that does not set `:dev_routes`.
    """

    @behaviour Plug

    import Plug.Conn

    alias GitSync.DevSeeds

    @impl Plug
    def init(options), do: options

    @impl Plug
    def call(%Plug.Conn{} = conn, _options) do
      {status, body} = answer(route(conn), conn)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, JSON.encode!(body))
    end

    # A `file://` base URL leaves the directory the seeded repositories are in
    # in front of the path, so a Forgejo request arrives with its API path
    # buried rather than at the root.
    defp route(%Plug.Conn{path_info: path}) do
      case Enum.split_while(path, &(&1 != "api")) do
        {_disk, ["api" | rest]} -> ["api" | rest]
        {path, []} -> path
      end
    end

    defp answer(["api", "v1", "user"], conn), do: authorized(conn, account())
    defp answer(["api", "v1", "user", "repos"], conn), do: authorized(conn, repos(:forgejo))

    defp answer(["user"], conn), do: authorized(conn, account())
    defp answer(["user", "repos"], conn), do: authorized(conn, repos(:github))

    defp answer(["xrpc", "com.atproto.identity.resolveHandle"], _conn),
      do: {200, %{did: DevSeeds.account().did}}

    defp answer(["did:" <> _rest], _conn), do: {200, document()}

    defp answer(["xrpc", "com.atproto.repo.describeRepo"], _conn),
      do: {200, %{did: DevSeeds.account().did}}

    defp answer(["xrpc", "com.atproto.repo.getRecord"], conn), do: knot(conn)

    defp answer(["xrpc", "com.atproto.repo.listRecords"], _conn), do: {200, %{records: records()}}

    defp answer(_path, _conn),
      do: {404, %{message: "GitSync.DevForge stands in for no such host"}}

    defp authorized(%Plug.Conn{} = conn, body) do
      if get_req_header(conn, "authorization") == ["Bearer " <> DevSeeds.token()],
        do: {200, body},
        else: {401, %{message: "GitSync.DevForge holds no such credential"}}
    end

    defp account, do: %{login: DevSeeds.operator(), id: 1}

    defp repos(kind) do
      repo = DevSeeds.repo(kind)

      [%{full_name: repo, clone_url: DevSeeds.clone_url(kind, repo), private: false}]
    end

    defp document do
      %{
        id: DevSeeds.account().did,
        alsoKnownAs: ["at://" <> DevSeeds.account().handle],
        service: [
          %{
            id: "#atproto_pds",
            type: "AtprotoPersonalDataServer",
            serviceEndpoint: DevSeeds.account().pds_url
          }
        ]
      }
    end

    # A knot record under the appview's own account is how Tangled says it runs
    # that knot, and so takes its pushes on the appview rather than the knot.
    defp knot(%Plug.Conn{} = conn) do
      appview = URI.parse(DevSeeds.account().base_url).host
      rkey = conn |> fetch_query_params() |> Map.fetch!(:query_params) |> Map.get("rkey")

      if Enum.any?(DevSeeds.knots(), &(&1.host == rkey and &1.ssh_host == appview)),
        do: {200, %{uri: "at://#{DevSeeds.account().did}/sh.tangled.knot/#{rkey}"}},
        else: {404, %{message: "GitSync.DevForge registers no such knot"}}
    end

    defp records do
      for knot <- DevSeeds.knots() do
        %{
          uri: "at://#{DevSeeds.account().did}/sh.tangled.repo/#{knot.repo}",
          value: %{knot: knot.host, name: knot.repo}
        }
      end
    end
  end
end
