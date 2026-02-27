defmodule Autoforge.Deployments.Workers.VmManagementWorker do
  @moduledoc """
  Oban worker that executes a VM management operation on demand.

  Loads the VmManagementOp, dispatches to the appropriate VmManager function,
  and updates the op state with results.
  """

  use Oban.Worker, queue: :deployments, max_attempts: 3

  alias Autoforge.Deployments.{VmManagementOp, VmManager}

  require Ash.Query
  require Logger

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    attempt * attempt * 30
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"vm_management_op_id" => op_id} = args}) do
    op =
      VmManagementOp
      |> Ash.Query.filter(id == ^op_id)
      |> Ash.read_one!(authorize?: false)

    case op do
      nil ->
        Logger.warning("VmManagementWorker: op #{op_id} not found")
        :ok

      %{state: state} when state in [:completed, :failed] ->
        Logger.info("VmManagementWorker: op #{op_id} already in #{state} state, skipping")
        :ok

      op ->
        execute_op(op, args)
    end
  end

  defp execute_op(op, args) do
    op = Ash.load!(op, [:vm_instance], authorize?: false)

    with {:ok, op} <- Ash.update(op, %{}, action: :start_running, authorize?: false) do
      case dispatch(op.operation_type, op.vm_instance, args) do
        {:ok, result} ->
          Ash.update(op, %{result: result}, action: :complete, authorize?: false)
          Logger.info("VmManagementWorker: op #{op.id} completed successfully")
          :ok

        {:error, reason} ->
          error_msg = inspect(reason)
          Ash.update(op, %{error_message: error_msg}, action: :fail, authorize?: false)
          Logger.error("VmManagementWorker: op #{op.id} failed: #{error_msg}")
          {:error, reason}
      end
    end
  end

  defp dispatch(:check_updates, vm_instance, _args), do: VmManager.check_updates(vm_instance)
  defp dispatch(:apply_updates, vm_instance, _args), do: VmManager.apply_updates(vm_instance)

  defp dispatch(:setup_usg, vm_instance, args) do
    pro_token = Map.get(args, "pro_token", "")
    audit? = Map.get(args, "audit", false)
    VmManager.setup_ubuntu_pro_usg(vm_instance, pro_token, audit: audit?)
  end

  defp dispatch(:restart, vm_instance, _args), do: VmManager.restart(vm_instance)
  defp dispatch(:docker_cleanup, vm_instance, _args), do: VmManager.docker_cleanup(vm_instance)
  defp dispatch(:health_check, vm_instance, _args), do: VmManager.check_services(vm_instance)

  defp dispatch(op_type, _vm_instance, _args), do: {:error, "Unknown operation: #{op_type}"}
end
