defmodule GitSyncTest do
  use ExUnit.Case
  doctest GitSync

  test "greets the world" do
    assert GitSync.hello() == :world
  end
end
