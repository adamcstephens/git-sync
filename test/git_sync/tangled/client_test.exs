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

  test "falls back to the timer instead of webhooks" do
    assert {:error, :unsupported} =
             Client.create_webhook(@connection, "adam/git-sync", "https://s.example/h", "shh")

    assert {:error, :unsupported} = Client.verify_webhook(@connection, [], "{}", "shh")
  end
end
