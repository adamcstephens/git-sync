defmodule GitSync.Forgejo.Provider do
  @moduledoc """
  Supervises the oidcc worker holding the Forgejo provider configuration.

  The issuer only becomes known when the wizard is completed, so the worker is
  started dynamically rather than listed in the application's children. It backs
  off and retries rather than terminating, so a Forgejo instance that is briefly
  unreachable does not leave the app with no way to log in.

  That patience is only worth spending on an issuer that could answer. A
  development instance points `base_url` at the bare repositories it clones
  from, and nothing is discoverable over `file://`, so a worker started on one
  would retry until the instance is shut down.
  """

  alias GitSync.Connection
  alias GitSync.Connections

  @supervisor GitSync.Forgejo.ProviderSupervisor
  @worker GitSync.Forgejo.ProviderWorker

  def child_spec(_opts),
    do: DynamicSupervisor.child_spec(name: @supervisor, strategy: :one_for_one)

  def name, do: @worker

  @doc """
  Whether a connection's Forgejo could be an OIDC issuer.
  """
  def issuer?(%Connection{base_url: base_url}),
    do: URI.parse(base_url).scheme in ["http", "https"]

  def issuer?(nil), do: false

  @doc """
  Starts the worker for `issuer`, replacing one pointing at a different issuer.
  """
  def ensure_started(issuer) do
    :ok = stop()
    start(issuer)
  end

  @doc """
  Stops the worker if one is running.
  """
  def stop do
    case Process.whereis(@worker) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(@supervisor, pid)
    end
  end

  @doc """
  Brings the worker up at boot when the wizard has already been completed.
  """
  def start_configured do
    case Connections.forgejo() do
      %Connection{client_id: client_id, base_url: base_url} = connection
      when is_binary(client_id) ->
        if issuer?(connection), do: ensure_started(base_url), else: :ignore

      _ ->
        :ignore
    end
  end

  defp start(issuer) do
    DynamicSupervisor.start_child(
      @supervisor,
      {Oidcc.ProviderConfiguration.Worker,
       %{
         issuer: issuer,
         name: @worker,
         backoff_min: :timer.seconds(1),
         backoff_max: :timer.minutes(1),
         backoff_type: :random_exponential
       }}
    )
  end
end
