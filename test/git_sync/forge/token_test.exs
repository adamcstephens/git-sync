defmodule GitSync.Forge.TokenTest do
  use ExUnit.Case, async: true

  alias GitSync.Forge.Token

  test "turns a lifetime in seconds into an absolute expiry" do
    token = Token.new("access", "refresh", 3600)

    assert token.access == "access"
    assert token.refresh == "refresh"
    assert DateTime.diff(token.expires_at, DateTime.utc_now()) in 3595..3600
  end

  test "a token whose lifetime the forge did not state never expires" do
    assert %Token{expires_at: nil} = Token.new("access", nil, nil)
  end

  test "a token is spent once its expiry is within the refresh margin" do
    refute Token.spent?(Token.new("access", "refresh", 3600))
    assert Token.spent?(Token.new("access", "refresh", 10))
    assert Token.spent?(Token.new("access", "refresh", -1))
    refute Token.spent?(Token.new("access", "refresh", nil))
  end
end
