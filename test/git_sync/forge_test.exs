defmodule GitSync.ForgeTest do
  use ExUnit.Case, async: true

  alias GitSync.Connection
  alias GitSync.Forge

  test "dispatches to the implementation for the connection's kind" do
    assert Forge.impl(%Connection{kind: :forgejo}) == GitSync.Forgejo.Client
    assert Forge.impl(%Connection{kind: :github}) == GitSync.Github.Client
    assert Forge.impl(%Connection{kind: :tangled}) == GitSync.Tangled.Client
  end

  test "every registered implementation adopts the behaviour" do
    for kind <- Connection.kinds() do
      module = Forge.impl(%Connection{kind: kind})
      Code.ensure_loaded!(module)

      assert Forge in module.module_info(:attributes)[:behaviour],
             "#{inspect(module)} does not implement GitSync.Forge"
    end
  end

  test "clone_url goes through the registry" do
    connection = %Connection{kind: :github, base_url: "https://github.com/"}

    assert Forge.clone_url(connection, "adam/git-sync", :read) ==
             "https://github.com/adam/git-sync"
  end
end
