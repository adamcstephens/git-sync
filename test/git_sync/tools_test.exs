defmodule GitSync.ToolsTest do
  use ExUnit.Case, async: true

  alias GitSync.Tools

  test "passes when every program is on PATH" do
    assert Tools.check!(["sh", "git"]) == :ok
  end

  test "names the programs that are missing" do
    error =
      assert_raise RuntimeError, fn ->
        Tools.check!(["sh", "not-a-real-program", "also-not-real"])
      end

    message = Exception.message(error)

    assert message =~ "not-a-real-program"
    assert message =~ "also-not-real"
    refute message =~ "sh,"
  end
end
