defmodule Autoforge.Deployments.Workers.DeployWorker do
  @moduledoc """
  Oban worker that deploys a project to a remote VM instance.
  """

  use Oban.Worker, queue: :deployments, max_attempts: 5

  alias Autoforge.Deployments.{Deployment, DeployOrchestrator}

  require Ash.Query
  require Logger

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    attempt * attempt * 30
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"deployment_id" => deployment_id}}) do
    deployment =
      Deployment
      |> Ash.Query.filter(id == ^deployment_id)
      |> Ash.read_one!(authorize?: false)

    case deployment do
      nil ->
        Logger.warning("DeployWorker: deployment #{deployment_id} not found")
        :ok

      %{state: state} when state in [:running, :destroying, :destroyed] ->
        Logger.info(
          "DeployWorker: deployment #{deployment_id} already in #{state} state, skipping"
        )

        :ok

      %{state: :error} ->
        Logger.info("DeployWorker: deployment #{deployment_id} in error state, retrying")
        do_deploy(deployment)

      deployment ->
        do_deploy(deployment)
    end
  end

  defp do_deploy(deployment) do
    case DeployOrchestrator.deploy(deployment) do
      {:ok, _deployment} ->
        Logger.info("DeployWorker: deployment #{deployment.id} completed successfully")
        :ok

      {:error, reason} ->
        Logger.error("DeployWorker: failed to deploy #{deployment.id}: #{inspect(reason)}")
        if rate_limited?(reason), do: {:snooze, 120}, else: {:error, reason}
    end
  end

  defp rate_limited?(reason) when is_binary(reason) do
    String.contains?(reason, "Rate Limit") or String.contains?(reason, "rateLimitExceeded")
  end

  defp rate_limited?(_), do: false
end
