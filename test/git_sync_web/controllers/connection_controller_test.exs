defmodule GitSyncWeb.ConnectionControllerTest do
  use GitSyncWeb.ConnCase

  alias GitSync.Connections
  alias GitSync.Forge.Token

  setup :configure_forgejo

  setup %{conn: conn, connection: connection} do
    {:ok, _connection} =
      GitSync.Connections.record_login(connection, "alice", Token.new("tok", nil, nil))

    %{conn: init_test_session(conn, %{"operator" => "alice"})}
  end

  test "shows the instance and its repositories", %{conn: conn} do
    Req.Test.stub(GitSync.Http, fn req_conn ->
      Req.Test.json(req_conn, [
        %{
          "full_name" => "alice/git-sync",
          "clone_url" => "https://forge.test/alice/git-sync.git",
          "private" => false
        }
      ])
    end)

    html = html_response(get(conn, ~p"/connections"), 200)

    assert html =~ "https://forge.test"
    assert html =~ "alice/git-sync"
  end

  test "reports why the repository list is unavailable", %{conn: conn} do
    Req.Test.stub(GitSync.Http, &Plug.Conn.send_resp(&1, 401, ""))

    assert html_response(get(conn, ~p"/connections"), 200) =~ "Could not list repositories"
  end

  describe "tangled" do
    setup %{conn: conn} do
      Req.Test.stub(GitSync.Http, &Plug.Conn.send_resp(&1, 401, ""))

      %{conn: conn}
    end

    test "offers a form for the account and nothing to paste", %{conn: conn} do
      html = html_response(get(conn, ~p"/connections"), 200)

      assert html =~ "tangled-form"
      assert html =~ "connection[handle]"
      refute html =~ "connection[ssh_key]"
    end

    test "saving an account resolves it and lists what it owns", %{conn: conn} do
      stub_tangled()

      saved = post(conn, ~p"/connections/tangled", %{"connection" => %{"handle" => "oppi.li"}})

      assert redirected_to(saved) == ~p"/connections"
      assert Connections.tangled().did == "did:plc:abc"

      html = html_response(get(conn, ~p"/connections"), 200)

      assert html =~ "oppi.li"
      assert html =~ "knot1.tangled.sh/oppi.li/git-sync"
    end

    test "an account already saved can be resolved again from its own form", %{conn: conn} do
      stub_tangled()
      post(conn, ~p"/connections/tangled", %{"connection" => %{"handle" => "oppi.li"}})

      html = html_response(get(conn, ~p"/connections"), 200)
      form = html |> String.split(~s(id="tangled-form")) |> Enum.at(1)

      refute form =~ ~s(name="_method")

      again = post(conn, ~p"/connections/tangled", %{"connection" => %{"handle" => "oppi.li"}})

      assert redirected_to(again) == ~p"/connections"
    end

    test "an account that cannot be resolved re-renders the page", %{conn: conn} do
      conn = post(conn, ~p"/connections/tangled", %{"connection" => %{"handle" => "nobody"}})

      assert html_response(conn, 200) =~ "No account could be found for nobody"
      refute Connections.tangled()
    end

    test "reports why the repository list is unavailable", %{conn: conn} do
      stub_tangled()
      post(conn, ~p"/connections/tangled", %{"connection" => %{"handle" => "oppi.li"}})

      Req.Test.stub(GitSync.Http, &Plug.Conn.send_resp(&1, 502, ""))

      assert html_response(get(conn, ~p"/connections"), 200) =~
               "Could not list Tangled repositories"
    end

    test "shows the fingerprints of the knots it has pinned", %{conn: conn} do
      stub_tangled()
      post(conn, ~p"/connections/tangled", %{"connection" => %{"handle" => "oppi.li"}})

      GitSync.Repo.insert!(%GitSync.Knot{
        connection_id: Connections.tangled().id,
        host: "knot1.tangled.sh",
        host_key: "knot1.tangled.sh ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIexample"
      })

      assert html_response(get(conn, ~p"/connections"), 200) =~ "knot1.tangled.sh"
    end

    test "generating a key shows the public half to copy", %{conn: conn} do
      stub_tangled()
      post(conn, ~p"/connections/tangled", %{"connection" => %{"handle" => "oppi.li"}})

      generated = post(conn, ~p"/connections/tangled/key")

      assert redirected_to(generated) == ~p"/connections"

      html = html_response(get(conn, ~p"/connections"), 200)

      assert html =~ Connections.tangled().public_key
      refute html =~ "BEGIN OPENSSH PRIVATE KEY"
    end

    test "there is nothing to generate a key for until an account is saved", %{conn: conn} do
      conn = post(conn, ~p"/connections/tangled/key")

      assert redirected_to(conn) == ~p"/connections"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "No Tangled account"
    end

    defp stub_tangled do
      Req.Test.stub(GitSync.Http, fn conn ->
        case conn.host do
          "public.api.bsky.app" ->
            Req.Test.json(conn, %{"did" => "did:plc:abc"})

          "plc.directory" ->
            Req.Test.json(conn, %{
              "alsoKnownAs" => ["at://oppi.li"],
              "service" => [
                %{
                  "type" => "AtprotoPersonalDataServer",
                  "serviceEndpoint" => "https://pds.example"
                }
              ]
            })

          "pds.example" ->
            Req.Test.json(conn, %{
              "records" => [
                %{
                  "uri" => "at://did:plc:abc/sh.tangled.repo/git-sync",
                  "value" => %{"knot" => "knot1.tangled.sh"}
                }
              ]
            })

          _forgejo ->
            Plug.Conn.send_resp(conn, 401, "")
        end
      end)
    end
  end
end
