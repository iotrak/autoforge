defmodule Autoforge.Projects.TemplateRenderer do
  @moduledoc """
  Renders Liquid templates for project files and scripts using Solid.
  """

  @doc """
  Renders a Liquid template string with the given variables.
  """
  def render_file(template_string, variables) when is_binary(template_string) do
    with {:ok, template} <- Solid.parse(template_string),
         {:ok, iolist} <- Solid.render(template, variables) do
      {:ok, IO.iodata_to_binary(iolist)}
    else
      {:error, _errors, iolist} ->
        {:ok, IO.iodata_to_binary(iolist)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Renders a bootstrap script template with project variables.
  """
  def render_script(nil, _variables), do: {:ok, ""}

  def render_script(script_template, variables) do
    render_file(script_template, variables)
  end

  @doc """
  Builds the template variables map for a project.
  """
  def build_variables(%{name: name, db_name: db_name, db_password: db_password} = project) do
    base = %{
      "project_name" => name,
      "db_host" => "db-#{project.id}",
      "db_port" => "5432",
      "db_name" => db_name,
      "db_test_name" => db_name <> "_test",
      "db_user" => "postgres",
      "db_password" => db_password
    }

    case project do
      %{env_vars: vars} when is_list(vars) ->
        Enum.reduce(vars, base, fn var, acc ->
          Map.put(acc, "env_#{String.downcase(var.key)}", var.value)
        end)

      _ ->
        base
    end
  end
end
