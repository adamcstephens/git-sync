defmodule GitSyncWeb.SessionHTML do
  @moduledoc """
  Pages rendered by SessionController.
  """
  use GitSyncWeb, :html

  embed_templates "session_html/*"
end
