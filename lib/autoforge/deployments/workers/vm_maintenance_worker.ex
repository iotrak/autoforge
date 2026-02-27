defmodule Autoforge.Deployments.Workers.VmMaintenanceWorker do
  @moduledoc """
  Daily cron Oban worker that runs maintenance checks on all running VMs.

  For each running VmInstance, creates VmManagementOp records for:
  - check_updates (OS update check)
  - health_check (service status)
  - docker_cleanup (prune unused resources)

  Individual VM failures are logged and skipped (don't block other VMs).
  """

  use Oban.Worker, queue: :deployments, max_attempts: 1

  alias Autoforge.Deployments.{VmInstance, VmManagementOp}

  require Ash.Query
  require Logger

  @maintenance_ops [:check_updates, :health_check, :docker_cleanup]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    running_vms =
      VmInstance
      |> Ash.Query.filter(state == :running)
      |> Ash.read!(authorize?: false)

    Logger.info("VmMaintenanceWorker: running maintenance on #{length(running_vms)} VMs")

    Enum.each(running_vms, fn vm_instance ->
      run_maintenance_for_vm(vm_instance)
    end)

    :ok
  end

  defp run_maintenance_for_vm(vm_instance) do
    Enum.each(@maintenance_ops, fn op_type ->
      case create_and_enqueue_op(vm_instance, op_type) do
        {:ok, _op} ->
          Logger.info("VmMaintenanceWorker: enqueued #{op_type} for VM #{vm_instance.id}")

        {:error, reason} ->
          Logger.warning(
            "VmMaintenanceWorker: failed to enqueue #{op_type} for VM #{vm_instance.id}: #{inspect(reason)}"
          )
      end
    end)
  rescue
    e ->
      Logger.error(
        "VmMaintenanceWorker: unexpected error for VM #{vm_instance.id}: #{Exception.message(e)}"
      )
  end

  defp create_and_enqueue_op(vm_instance, op_type) do
    with {:ok, op} <-
           Ash.create(
             VmManagementOp,
             %{
               operation_type: op_type,
               triggered_by: :scheduled,
               vm_instance_id: vm_instance.id
             },
             action: :create,
             authorize?: false
           ) do
      %{vm_management_op_id: op.id}
      |> Autoforge.Deployments.Workers.VmManagementWorker.new()
      |> Oban.insert!()

      {:ok, op}
    end
  end
end
