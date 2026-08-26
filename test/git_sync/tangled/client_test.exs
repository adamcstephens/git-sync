defmodule GitSync.Tangled.ClientTest do
  use ExUnit.Case, async: true

  alias GitSync.Connection
  alias GitSync.Tangled.Client

  @connection %Connection{kind: :tangled, base_url: "https://knot.example/"}

  test "has no repository listing to offer" do
    assert {:error, :unsupported} = Client.list_repos(@connection)
  end

  test "reads over https" do
    assert Client.clone_url(@connection, "adam/git-sync", :read) ==
             "https://knot.example/adam/git-sync"
  end

  test "writes over ssh as the knot's git user" do
    assert Client.clone_url(@connection, "adam/git-sync", :write) ==
             "git@knot.example:adam/git-sync"
  end

  test "reads a repo on another knot through the appview all the same" do
    assert Client.clone_url(@connection, "git.example.com/adam/git-sync", :read) ==
             "https://knot.example/adam/git-sync"
  end

  test "writes a repo on another knot straight to that knot" do
    assert Client.clone_url(@connection, "git.example.com/adam/git-sync", :write) ==
             "git@git.example.com:adam/git-sync"
  end

  test "names the knot a repo lives on" do
    assert Client.knot_host(@connection, "git.example.com/adam/git-sync") == "git.example.com"
    assert Client.knot_host(@connection, "adam/git-sync") == nil
  end

  test "falls back to the timer instead of webhooks" do
    assert {:error, :unsupported} =
             Client.create_webhook(@connection, "adam/git-sync", "https://s.example/h", "shh")

    assert {:error, :unsupported} = Client.verify_webhook(@connection, [], "{}", "shh")
  end
end
