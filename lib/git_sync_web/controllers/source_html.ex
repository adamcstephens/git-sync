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
    <section id="runs" class="gs-run-list">
      <p :if={@runs == []} class="gs-panel gs-muted">No runs yet.</p>

      <article :for={run <- @runs} id={"run-#{run.id}"} class="run gs-source-card">
        <div class="gs-run-head">
          <h3 data-status={run.status}>
            <span class={[
              "gs-badge",
              case run.status do
                :success -> "is-success"
                :failure -> "is-failed"
                :running -> "is-running"
              end
            ]}>
              {run.status}
            </span>
            <span class="gs-muted gs-mono">Run #{run.id}</span>
          </h3>
          <p class="gs-muted gs-mono">
            Started <time datetime={DateTime.to_iso8601(run.started_at)}>{run.started_at}</time>
            <span :if={run.finished_at}>
              · finished
              <time datetime={DateTime.to_iso8601(run.finished_at)}>{run.finished_at}</time>
            </span>
          </p>
        </div>
        <div class="gs-run-body">
          <div :if={run.log}>
            <h4 class="gs-eyebrow">Source log</h4>
            <pre class="gs-log">{run.log}</pre>
          </div>
          <h4 class="gs-eyebrow">Destination results</h4>
          <p :if={run.targets == []} class="gs-muted">No destination results recorded.</p>
          <article
            :for={target <- run.targets}
            id={"run-target-#{target.id}"}
            class="run-target gs-run-target"
          >
            <div class="gs-run-head">
              <h4 class="gs-mono" data-status={target.status}>
                {target.destination.repo}
                <span class="gs-muted">on {target.destination.connection.base_url}</span>
              </h4>
              <span
                data-status={target.status}
                class={[
                  "gs-badge",
                  if(target.status == :success, do: "is-success", else: "is-failed")
                ]}
              >
                {target.status}
              </span>
            </div>
            <p :if={target.refs_pushed == []} class="gs-muted">No refs pushed.</p>
            <p :if={target.refs_pushed != []} class="gs-ref-list gs-mono">
              Pushed {Enum.join(target.refs_pushed, ", ")}
            </p>
            <div :if={target.log}>
              <h6 class="gs-eyebrow">Destination log</h6>
              <pre class="gs-log">{target.log}</pre>
            </div>
          </article>
        </div>
      </article>
    </section>
    """
  end
end
