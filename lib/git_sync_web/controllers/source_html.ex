defmodule GitSyncWeb.SourceHTML do
  @moduledoc """
  Source management and run history pages.
  """
  use GitSyncWeb, :html

  embed_templates "source_html/*"

  @doc """
  A repository picker for one end of a mirror. A forge that can be listed
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
  The forge picker for one end of a mirror, which repaints the repository
  picker beside it as it changes.
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :options, :list, required: true

  def forge_field(assigns) do
    ~H"""
    <.input
      field={@field}
      type="select"
      label={@label}
      options={@options}
      prompt="Choose a forge"
      data-bind={"#{@field.form.name}_connection_id"}
      data-on:change={"@get('#{~p"/sources/repos"}')"}
    />
    """
  end

  @doc """
  The run history of one source, patched into the page as runs happen.
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
        <pre :if={run.log}>{run.log}</pre>

        <article :for={target <- run.targets} id={"run-target-#{target.id}"} class="run-target">
          <h4 data-status={target.status}>
            {target.destination.repo} on {target.destination.connection.base_url}: {target.status}
          </h4>
          <p :if={target.refs_pushed != []}>Pushed {Enum.join(target.refs_pushed, ", ")}</p>
          <pre :if={target.log}>{target.log}</pre>
        </article>
      </article>
    </section>
    """
  end
end
