defmodule GitSyncWeb.LayoutsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias GitSyncWeb.Layouts

  describe "app/1" do
    test "renders the flash group between the header and the main content" do
      html =
        render_component(&Layouts.app/1, %{
          flash: %{"info" => "Saved."},
          current_operator: "operator",
          inner_block: inner_block("hello")
        })

      assert [_, after_header] = String.split(html, "</header>")
      assert [flash_group, _] = String.split(after_header, "<main>")
      assert flash_group =~ ~s(id="flash-group")
      assert flash_group =~ "Saved."
    end
  end

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

  defp inner_block(content) do
    [%{__slot__: :inner_block, inner_block: fn _, _ -> content end}]
  end
end
