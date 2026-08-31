defmodule GitSyncWeb.ConnectionHTML do
  @moduledoc """
  Connection status pages.
  """
  use GitSyncWeb, :html

  embed_templates "connection_html/*"

  @doc """
  How a connection is faring, standing in for the repository listing the page
  used to render in full.
  """
  attr :id, :string, required: true
  attr :health, :any, required: true

  def health(assigns) do
    ~H"""
    <span id={@id} class="health" data-health={state(@health)}>
      <%= case @health do %>
        <% :ok -> %>
          Healthy
        <% {:error, reason} -> %>
          Unreachable — {reason}
        <% :disconnected -> %>
          Not connected
        <% nil -> %>
          Not configured
      <% end %>
    </span>
    """
  end

  defp state(:ok), do: "ok"
  defp state({:error, _reason}), do: "error"
  defp state(other), do: to_string(other || "none")
end
