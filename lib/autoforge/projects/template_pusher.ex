defmodule Autoforge.Projects.TemplatePusher do
  @moduledoc """
  Pushes template file updates to project containers.

  Re-renders all template files and uploads them to the container,
  overwriting existing files. Does not re-run bootstrap or startup scripts.

  For stopped projects, the container is temporarily started at the Docker
  level to upload files, then stopped again. The Ash project state is not
  changed.
  """

  alias Autoforge.Projects.{
    Docker,
    Project,
    ProjectTemplateFile,
    TarBuilder,
    TemplateRenderer,
    Workers.TemplatePushWorker
  }

  require Ash.Query
  require Logger

  @doc """
  Pushes template files to a single project's container.

  The project must be in `:running` or `:stopped` state with a valid `container_id`.
  Stopped projects have their container temporarily started for the upload.

  Options:
    * `:file_ids` - list of `ProjectTemplateFile` IDs to push. When omitted,
      all template files are pushed. For directories, include the directory and
      all descendant IDs.

  Returns `{:ok, %{file_count: integer()}}` on success.
  """
  def push_to_project(project, opts \\ []) do
    project = Ash.load!(project, [:project_template, :env_vars, :user], authorize?: false)
    file_ids = Keyword.get(opts, :file_ids)

    with :ok <- validate_pushable(project) do
      if project.state == :stopped do
        push_to_stopped(project, file_ids)
      else
        push_and_broadcast(project, file_ids)
      end
    end
  end

  @doc """
  Enqueues template push jobs for all running and stopped projects using the
  given template.

  Options:
    * `:file_ids` - list of `ProjectTemplateFile` IDs to push. When omitted,
      all template files are pushed.

  Returns `{:ok, %{project_count: integer()}}`.
  """
  def push_to_all_projects(template, opts \\ []) do
    file_ids = Keyword.get(opts, :file_ids)

    projects =
      Project
      |> Ash.Query.filter(project_template_id == ^template.id and state in [:running, :stopped])
      |> Ash.read!(authorize?: false)

    Enum.each(projects, fn project ->
      args = %{"project_id" => project.id}
      args = if file_ids, do: Map.put(args, "file_ids", file_ids), else: args

      args
      |> TemplatePushWorker.new()
      |> Oban.insert!()
    end)

    {:ok, %{project_count: length(projects)}}
  end

  defp validate_pushable(%{state: state, container_id: id})
       when state in [:running, :stopped] and is_binary(id),
       do: :ok

  defp validate_pushable(%{container_id: nil}), do: {:error, "Project has no container"}
  defp validate_pushable(%{state: state}), do: {:error, "Project is #{state}, cannot push"}

  defp push_and_broadcast(project, file_ids) do
    with {:ok, file_count} <- upload_files(project, file_ids) do
      broadcast(project, "Template files updated (#{file_count} files)")
      {:ok, %{file_count: file_count}}
    end
  end

  defp push_to_stopped(project, file_ids) do
    with :ok <- Docker.start_container(project.container_id) do
      result = upload_files(project, file_ids)
      Docker.stop_container(project.container_id, timeout: 5)

      case result do
        {:ok, file_count} ->
          broadcast(project, "Template files updated (#{file_count} files)")
          {:ok, %{file_count: file_count}}

        error ->
          error
      end
    end
  end

  defp upload_files(project, file_ids) do
    all_files =
      ProjectTemplateFile
      |> Ash.Query.filter(project_template_id == ^project.project_template_id)
      |> Ash.read!(authorize?: false)

    case all_files do
      [] ->
        {:ok, 0}

      all_files ->
        variables = TemplateRenderer.build_variables(project)

        with {:ok, tar_binary} <-
               TarBuilder.build_from_template_files(all_files, variables, file_ids),
             :ok <- Docker.put_archive(project.container_id, "/app", tar_binary),
             {:ok, %{exit_code: 0}} <-
               Docker.exec_run(project.container_id, ["chown", "-R", "app:app", "/app"]) do
          pushed = if file_ids, do: length(file_ids), else: length(all_files)
          {:ok, pushed}
        else
          {:ok, %{exit_code: code, output: output}} ->
            {:error, "chown failed (exit #{code}): #{output}"}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp broadcast(project, message) do
    Phoenix.PubSub.broadcast(
      Autoforge.PubSub,
      "project:template_push:#{project.id}",
      {:template_push, message}
    )

    Phoenix.PubSub.broadcast(
      Autoforge.PubSub,
      "template:push_complete:#{project.project_template_id}",
      {:template_push_complete, project.id, message}
    )
  end
end
