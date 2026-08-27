defmodule GitSync.Tangled.IdentityTest do
  use ExUnit.Case, async: true

  alias GitSync.Tangled.Identity

  defp stub(fun), do: Req.Test.stub(GitSync.Http, fun)

  defp did_doc(pds) do
    %{
      "id" => "did:plc:abc",
      "alsoKnownAs" => ["at://oppi.li"],
      "service" => [
        %{"id" => "#atproto_pds", "type" => "AtprotoPersonalDataServer", "serviceEndpoint" => pds}
      ]
    }
  end

  defp directory(conn), do: Req.Test.json(conn, did_doc("https://pds.example"))

  test "resolves a handle to its did, canonical handle and pds" do
    stub(fn conn ->
      case {conn.host, conn.request_path} do
        {"public.api.bsky.app", "/xrpc/com.atproto.identity.resolveHandle"} ->
          conn = Plug.Conn.fetch_query_params(conn)
          assert conn.query_params["handle"] == "oppi.li"

          Req.Test.json(conn, %{"did" => "did:plc:abc"})

        {"plc.directory", "/did:plc:abc"} ->
          directory(conn)
      end
    end)

    assert {:ok, identity} = Identity.resolve("oppi.li")

    assert identity == %{
             did: "did:plc:abc",
             handle: "oppi.li",
             pds_url: "https://pds.example"
           }
  end

  test "a did needs no handle lookup" do
    stub(fn conn ->
      assert conn.host == "plc.directory"

      directory(conn)
    end)

    assert {:ok, %{did: "did:plc:abc", handle: "oppi.li"}} = Identity.resolve("did:plc:abc")
  end

  test "a handle may be written the way Tangled displays it" do
    stub(fn conn ->
      case conn.host do
        "public.api.bsky.app" ->
          conn = Plug.Conn.fetch_query_params(conn)
          assert conn.query_params["handle"] == "oppi.li"

          Req.Test.json(conn, %{"did" => "did:plc:abc"})

        "plc.directory" ->
          directory(conn)
      end
    end)

    assert {:ok, %{handle: "oppi.li"}} = Identity.resolve("@oppi.li")
  end

  test "reads a DID document the directory serves as linked data" do
    stub(fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/did+ld+json")
      |> Plug.Conn.send_resp(200, JSON.encode!(did_doc("https://pds.example")))
    end)

    assert {:ok, %{pds_url: "https://pds.example"}} = Identity.resolve("did:plc:abc")
  end

  test "reports a handle nobody answers for" do
    stub(fn conn -> Plug.Conn.send_resp(conn, 400, "") end)

    assert {:error, "No account could be found for nobody.example"} =
             Identity.resolve("nobody.example")
  end

  test "reports a did the directory does not hold" do
    stub(fn conn -> Plug.Conn.send_resp(conn, 404, "") end)

    assert {:error, "The directory returned HTTP 404 for did:plc:abc"} =
             Identity.resolve("did:plc:abc")
  end

  test "reports an account with no repository server to read from" do
    stub(fn conn ->
      Req.Test.json(conn, Map.put(did_doc("https://pds.example"), "service", []))
    end)

    assert {:error, "did:plc:abc has no atproto PDS to list repositories from"} =
             Identity.resolve("did:plc:abc")
  end

  test "reports an unreachable directory" do
    stub(fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

    assert {:error, "connection refused"} = Identity.resolve("did:plc:abc")
  end
end
