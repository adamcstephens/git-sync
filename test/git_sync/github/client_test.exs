defmodule GitSync.Github.ClientTest do
  use ExUnit.Case, async: true

  alias GitSync.Connection
  alias GitSync.Github.Client

  @connection %Connection{base_url: "https://github.com", token: "gho_tok"}

  defp stub(fun), do: Req.Test.stub(GitSync.Http, fun)

  test "lists the repositories the token can reach" do
    stub(fn conn ->
      assert conn.host == "api.github.com"
      assert conn.request_path == "/user/repos"
      assert ["Bearer gho_tok"] = Plug.Conn.get_req_header(conn, "authorization")

      Req.Test.json(conn, [
        %{
          "full_name" => "adam/git-sync",
          "clone_url" => "https://github.com/adam/git-sync.git",
          "private" => true
        }
      ])
    end)

    assert {:ok, [%{full_name: "adam/git-sync", private: true}]} = Client.list_repos(@connection)
  end

  test "reports an unauthorized response" do
    stub(fn conn -> Plug.Conn.send_resp(conn, 401, "") end)

    assert {:error, "GitHub returned HTTP 401"} = Client.list_repos(@connection)
  end
end
