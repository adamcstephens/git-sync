defmodule GitSyncWeb.ConnectionHTML do
  @moduledoc """
  Connection status pages.
  """
  use GitSyncWeb, :html

  embed_templates "connection_html/*"
end
