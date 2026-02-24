defmodule Autoforge.Projects.Workers.CleanupWorker do
  @moduledoc """
  Oban cron worker that stops projects idle for more than 30 minutes.
  Runs every 5 minutes.
  """

  use Oban.Worker, queue: :sandbox, max_attempts: 1

  alias Autoforge.Projects.{Project, Sandbox}

  require Ash.Query
  require Logger

  @idle_threshold_minutes 30

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    cutoff = DateTime.add(DateTime.utc_now(), -@idle_threshold_minutes, :minute)

    idle_projects =
      Project
      |> Ash.Query.filter(state == :running and last_activity_at < ^cutoff)
      |> Ash.read!(authorize?: false)

    for project <- idle_projects do
      Logger.info("CleanupWorker: stopping idle project #{project.id} (#{project.name})")

      case Sandbox.stop(project) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("CleanupWorker: failed to stop #{project.id}: #{inspect(reason)}")
      end
    end

    :ok
  end
end
