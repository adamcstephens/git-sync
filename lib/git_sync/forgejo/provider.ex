defmodule GitSync.Forgejo.Provider do
  @moduledoc """
  Supervises the oidcc worker holding the Forgejo provider configuration.

  The issuer only becomes known when the wizard is completed, so the worker is
  started dynamically rather than listed in the application's children.
  """

  alias GitSync.Connection
  alias GitSync.Connections

  @supervisor GitSync.Forgejo.ProviderSupervisor
  @worker GitSync.Forgejo.ProviderWorker

  def child_spec(_opts),
    do: DynamicSupervisor.child_spec(name: @supervisor, strategy: :one_for_one)

  def name, do: @worker

  @doc """
  Starts the worker for `issuer`, replacing one pointing at a different issuer.
  """
  def ensure_started(issuer) do
    case Process.whereis(@worker) do
      nil ->
        start(issuer)

      pid ->
        :ok = DynamicSupervisor.terminate_child(@supervisor, pid)
        start(issuer)
    end
  end

  @doc """
  Brings the worker up at boot when the wizard has already been completed.
  """
  def start_configured do
    case Connections.forgejo() do
      %Connection{client_id: client_id, base_url: base_url} when is_binary(client_id) ->
        ensure_started(base_url)

      _ ->
        :ignore
    end
  end

  defp start(issuer) do
    DynamicSupervisor.start_child(
      @supervisor,
      {Oidcc.ProviderConfiguration.Worker, %{issuer: issuer, name: @worker}}
    )
  end
end
