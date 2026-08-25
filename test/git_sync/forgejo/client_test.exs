defmodule GitSync.Forgejo.ClientTest do
  use ExUnit.Case, async: true

  alias GitSync.Connection
  alias GitSync.Forgejo.Client

  @connection %Connection{base_url: "https://codeberg.org/", token: "tok"}

  defp stub(fun), do: Req.Test.stub(GitSync.Http, fun)

  test "lists the operator's repositories" do
    stub(fn conn ->
      assert conn.request_path == "/api/v1/user/repos"
      assert ["Bearer tok"] = Plug.Conn.get_req_header(conn, "authorization")

      Req.Test.json(conn, [
        %{
          "full_name" => "adam/git-sync",
          "clone_url" => "https://codeberg.org/adam/git-sync.git",
          "private" => false
        }
      ])
    end)

    assert {:ok, [%{full_name: "adam/git-sync", private: false}]} = Client.list_repos(@connection)
  end

  test "reports an unauthorized response" do
    stub(fn conn -> Plug.Conn.send_resp(conn, 401, "") end)

    assert {:error, "Forgejo returned HTTP 401"} = Client.list_repos(@connection)
  end
end
