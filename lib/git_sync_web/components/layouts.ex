defmodule GitSyncWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use GitSyncWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_operator, :string, default: nil, doc: "the signed-in operator, if any"
  attr :active_page, :atom, default: nil, values: [nil, :overview, :sources, :connections]

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class={["gs-shell", !@current_operator && "gs-shell-public"]}>
      <a href="#main-content" class="gs-skip-link">Skip to content</a>
      <aside :if={@current_operator} class="gs-sidebar">
        <a href={~p"/"} class="gs-brand">git-sync</a>
        <p class="gs-nav-label">Workspace</p>
        <nav class="gs-nav" aria-label="Main navigation">
          <.link href={~p"/"} aria-current={@active_page == :overview && "page"}>
            Overview
          </.link>
          <.link href={~p"/sources"} aria-current={@active_page == :sources && "page"}>
            Sources
          </.link>
          <.link href={~p"/connections"} aria-current={@active_page == :connections && "page"}>
            Connections
          </.link>
        </nav>
        <div class="gs-sidebar-bottom">
          <strong>Mirror operations</strong>
          <span>Repository sync control center</span>
          <.link href={~p"/logout"} method="delete">Sign out</.link>
        </div>
      </aside>
      <div class="gs-content">
        <header class="gs-topbar">
          <%= if @current_operator do %>
            <span class="gs-crumb">
              Workspace / {case @active_page do
                :overview -> "Overview"
                :sources -> "Sources"
                :connections -> "Connections"
                nil -> "Mirror operations"
              end}
            </span>
            <span class="gs-operator">Operator <strong>{@current_operator}</strong></span>
          <% else %>
            <a href={~p"/"} class="gs-brand">git-sync</a>
            <span class="gs-muted">Repository mirror operations</span>
          <% end %>
        </header>
        <.flash_group flash={@flash} />
        <main id="main-content" class="gs-main" tabindex="-1">
          {render_slot(@inner_block)}
        </main>
      </div>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end
end
