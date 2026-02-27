defmodule Autoforge.Projects.Workers.TemplatePushWorker do
  @moduledoc """
  Oban worker that pushes template file updates to a project's container.
  """

  use Oban.Worker, queue: :sandbox, max_attempts: 3

  alias Autoforge.Projects.{Project, TemplatePusher}

  require Ash.Query
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{"project_id" => project_id} = args
    file_ids = args["file_ids"]

    project =
      Project
      |> Ash.Query.filter(id == ^project_id)
      |> Ash.read_one!(authorize?: false)

    case project do
      nil ->
        Logger.warning("TemplatePushWorker: project #{project_id} not found")
        :ok

      %{state: state} when state not in [:running, :stopped] ->
        Logger.info("TemplatePushWorker: project #{project_id} is #{state}, skipping")
        :ok

      project ->
        opts = if file_ids, do: [file_ids: file_ids], else: []

        case TemplatePusher.push_to_project(project, opts) do
          {:ok, %{file_count: count}} ->
            Logger.info("TemplatePushWorker: pushed #{count} files to project #{project_id}")
            :ok

          {:error, reason} ->
            Logger.error(
              "TemplatePushWorker: failed to push to #{project_id}: #{inspect(reason)}"
            )

            {:error, reason}
        end
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    attempt * attempt * 30
  end
end
