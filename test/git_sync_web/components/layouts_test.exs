defmodule GitSyncWeb.LayoutsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  describe "flash/1" do
    test "marks the close button so a delegated listener can dismiss it" do
      html =
        render_component(&GitSyncWeb.CoreComponents.flash/1, %{
          kind: :info,
          flash: %{"info" => "Saved."}
        })

      assert html =~ "data-flash-close"
    end

    test "marks info flashes for auto-dismiss but not error flashes" do
      info =
        render_component(&GitSyncWeb.CoreComponents.flash/1, %{
          kind: :info,
          flash: %{"info" => "Saved."}
        })

      error =
        render_component(&GitSyncWeb.CoreComponents.flash/1, %{
          kind: :error,
          flash: %{"error" => "Nope."}
        })

      assert info =~ "data-flash-autodismiss"
      refute error =~ "data-flash-autodismiss"
    end
  end
end
