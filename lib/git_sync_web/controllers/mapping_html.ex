defmodule GitSyncWeb.MappingHTML do
  @moduledoc """
  Mapping management and run history pages.
  """
  use GitSyncWeb, :html

  embed_templates "mapping_html/*"

  @doc """
  A repository picker for one end of a mapping. A forge that can be listed
  gives a searchable list of its repositories; anything else falls back to a
  typed `owner/name`.
  """
  attr :id, :string, required: true
  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :repos, :any, required: true, doc: "`Forge.list_repos/1` result, or nil for no forge yet"

  def repo_field(assigns) do
    ~H"""
    <div id={@id}>
      <.repo_input field={@field} label={@label} repos={@repos} />
    </div>
    """
  end

  defp repo_input(%{repos: {:ok, repos}} = assigns) do
    assigns = assign(assigns, :options, Enum.map(repos, & &1.full_name))

    ~H"""
    <.input
      field={@field}
      type="datalist"
      label={@label}
      options={@options}
      placeholder="Type to search"
      autocomplete="off"
      data-1p-ignore
      data-lpignore="true"
    />
    """
  end

  defp repo_input(%{repos: nil} = assigns) do
    ~H"""
    <.input
      field={@field}
      type="select"
      label={@label}
      options={[]}
      prompt="Choose a forge first"
      disabled
    />
    """
  end

  defp repo_input(assigns) do
    ~H"""
    <.input
      field={@field}
      label={@label}
      placeholder="adam/git-sync"
      autocomplete="off"
      data-1p-ignore
      data-lpignore="true"
    />
    <p class="field-error">Could not list repositories: {elem(@repos, 1)}</p>
    """
  end

  @doc """
  The run history of one mapping, patched into the page as runs happen.
  """
  attr :runs, :list, required: true

  def runs(assigns) do
    ~H"""
    <section id="runs">
      <p :if={@runs == []}>No runs yet.</p>

      <article :for={run <- @runs} id={"run-#{run.id}"} class="run">
        <h3 data-status={run.status}>{run.status}</h3>
        <p>
          Started {run.started_at}<span :if={run.finished_at}>, finished {run.finished_at}</span>
        </p>
        <p :if={run.refs_pushed != []}>Pushed {Enum.join(run.refs_pushed, ", ")}</p>
        <pre :if={run.log}>{run.log}</pre>
      </article>
    </section>
    """
  end
end
