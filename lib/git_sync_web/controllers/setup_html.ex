defmodule GitSyncWeb.SetupHTML do
  @moduledoc """
  The first-run wizard.
  """
  use GitSyncWeb, :html

  embed_templates "setup_html/*"
end
