defmodule Autoforge.Repo.Migrations.AddGithubTools do
  use Ecto.Migration

  @github_tools [
    {"github_get_repo", "Get information about a GitHub repository."},
    {"github_list_issues", "List issues in a GitHub repository."},
    {"github_create_issue", "Create a new issue in a GitHub repository."},
    {"github_get_issue", "Get details of a specific GitHub issue."},
    {"github_comment_on_issue", "Add a comment to a GitHub issue or pull request."},
    {"github_list_pull_requests", "List pull requests in a GitHub repository."},
    {"github_create_pull_request", "Create a new pull request in a GitHub repository."},
    {"github_get_pull_request", "Get details of a specific pull request."},
    {"github_merge_pull_request", "Merge a pull request in a GitHub repository."},
    {"github_get_file", "Get the content of a file from a GitHub repository."},
    {"github_list_workflow_runs", "List GitHub Actions workflow runs for a repository."},
    {"github_get_workflow_run_logs", "Download logs for a GitHub Actions workflow run."}
  ]

  def up do
    for {name, description} <- @github_tools do
      execute """
      INSERT INTO tools (id, name, description, inserted_at, updated_at)
      VALUES (gen_random_uuid(), '#{name}', '#{description}', now(), now())
      ON CONFLICT (name) DO NOTHING
      """
    end
  end

  def down do
    names =
      @github_tools
      |> Enum.map(fn {name, _} -> "'#{name}'" end)
      |> Enum.join(", ")

    execute "DELETE FROM tools WHERE name IN (#{names})"
  end
end
