defmodule Autoforge.Deployments.Workers.BuildWorker do
  @moduledoc """
  Oban worker that builds a Docker image on the target VM
  and then enqueues a DeployWorker to deploy it.
  """

  use Oban.Worker, queue: :deployments, max_attempts: 3

  alias Autoforge.Deployments.{Deployment, ImageBuilder}

  require Ash.Query
  require Logger

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    attempt * attempt * 60
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"deployment_id" => deployment_id} = args}) do
    tag = Map.get(args, "tag", "latest")

    deployment =
      Deployment
      |> Ash.Query.filter(id == ^deployment_id)
      |> Ash.read_one!(authorize?: false)

    case deployment do
      nil ->
        Logger.warning("BuildWorker: deployment #{deployment_id} not found")
        :ok

      %{state: state} when state in [:destroying, :destroyed] ->
        Logger.info("BuildWorker: deployment #{deployment_id} in #{state} state, skipping")
        :ok

      deployment ->
        do_build_and_deploy(deployment, tag)
    end
  end

  defp do_build_and_deploy(deployment, tag) do
    case ImageBuilder.build_and_push(deployment, tag: tag) do
      {:ok, image_ref} ->
        Logger.info("BuildWorker: image built for #{deployment.id}: #{image_ref}")

        # Update the image reference then trigger a deploy
        case Ash.update(deployment, %{image: image_ref},
               action: :update_image,
               authorize?: false
             ) do
          {:ok, deployment} ->
            # Use :redeploy for states that support it, otherwise enqueue
            # DeployWorker directly (e.g. for :pending state)
            if deployment.state in [:running, :stopped, :error] do
              Ash.update(deployment, %{}, action: :redeploy, authorize?: false)
            else
              %{deployment_id: deployment.id}
              |> Autoforge.Deployments.Workers.DeployWorker.new()
              |> Oban.insert!()
            end

            :ok

          {:error, reason} ->
            Logger.error(
              "BuildWorker: failed to update image for #{deployment.id}: #{inspect(reason)}"
            )

            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("BuildWorker: failed to build #{deployment.id}: #{inspect(reason)}")

        Ash.update(deployment, %{error_message: "Build failed: #{inspect(reason)}"},
          action: :mark_error,
          authorize?: false
        )

        {:error, reason}
    end
  end
end
