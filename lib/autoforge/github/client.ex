defmodule Autoforge.GitHub.Client do
  @moduledoc """
  Thin Req wrapper over the GitHub REST API.

  Every function takes a `token` (fine-grained PAT) as the first argument
  and returns `{:ok, body}` or `{:error, term}`.
  """

  # ── User ───────────────────────────────────────────────────────────────────

  def get_authenticated_user(token) do
    github_req(token, :get, "/user")
  end

  # ── Repositories ───────────────────────────────────────────────────────────

  def create_repo(token, params) do
    github_req(token, :post, "/user/repos", json: params)
  end

  def create_org_repo(token, org, params) do
    github_req(token, :post, "/orgs/#{org}/repos", json: params)
  end

  def get_repo(token, owner, repo) do
    github_req(token, :get, "/repos/#{owner}/#{repo}")
  end

  # ── Repository Contents ────────────────────────────────────────────────────

  def get_file_content(token, owner, repo, path) do
    case github_req(token, :get, "/repos/#{owner}/#{repo}/contents/#{path}") do
      {:ok, %{"content" => encoded} = body} ->
        decoded =
          encoded
          |> String.replace(~r/\s/, "")
          |> Base.decode64!()

        {:ok, Map.put(body, "decoded_content", decoded)}

      other ->
        other
    end
  end

  def list_directory(token, owner, repo, path) do
    github_req(token, :get, "/repos/#{owner}/#{repo}/contents/#{path}")
  end

  # ── Issues ─────────────────────────────────────────────────────────────────

  def list_issues(token, owner, repo, opts \\ []) do
    params = Keyword.take(opts, [:state, :labels, :sort, :direction, :per_page, :page])
    github_req(token, :get, "/repos/#{owner}/#{repo}/issues", params: params)
  end

  def create_issue(token, owner, repo, params) do
    github_req(token, :post, "/repos/#{owner}/#{repo}/issues", json: params)
  end

  def get_issue(token, owner, repo, number) do
    github_req(token, :get, "/repos/#{owner}/#{repo}/issues/#{number}")
  end

  def create_issue_comment(token, owner, repo, number, body) do
    github_req(token, :post, "/repos/#{owner}/#{repo}/issues/#{number}/comments",
      json: %{"body" => body}
    )
  end

  # ── Pull Requests ──────────────────────────────────────────────────────────

  def list_pull_requests(token, owner, repo, opts \\ []) do
    params = Keyword.take(opts, [:state, :sort, :direction, :per_page, :page])
    github_req(token, :get, "/repos/#{owner}/#{repo}/pulls", params: params)
  end

  def create_pull_request(token, owner, repo, params) do
    github_req(token, :post, "/repos/#{owner}/#{repo}/pulls", json: params)
  end

  def get_pull_request(token, owner, repo, number) do
    github_req(token, :get, "/repos/#{owner}/#{repo}/pulls/#{number}")
  end

  def create_pr_comment(token, owner, repo, number, body) do
    create_issue_comment(token, owner, repo, number, body)
  end

  def merge_pull_request(token, owner, repo, number, opts \\ []) do
    json =
      opts
      |> Keyword.take([:commit_title, :commit_message, :merge_method])
      |> Map.new()

    github_req(token, :put, "/repos/#{owner}/#{repo}/pulls/#{number}/merge", json: json)
  end

  # ── Actions / Workflow Runs ────────────────────────────────────────────────

  def list_workflow_runs(token, owner, repo, opts \\ []) do
    params = Keyword.take(opts, [:branch, :event, :status, :per_page, :page])
    github_req(token, :get, "/repos/#{owner}/#{repo}/actions/runs", params: params)
  end

  def get_workflow_run(token, owner, repo, run_id) do
    github_req(token, :get, "/repos/#{owner}/#{repo}/actions/runs/#{run_id}")
  end

  def download_workflow_run_logs(token, owner, repo, run_id) do
    github_req(token, :get, "/repos/#{owner}/#{repo}/actions/runs/#{run_id}/logs", raw: true)
  end

  # ── Private ────────────────────────────────────────────────────────────────

  defp github_req(token, method, path, opts \\ []) do
    {json_opt, opts} = Keyword.pop(opts, :json)
    {raw, opts} = Keyword.pop(opts, :raw, false)

    req_opts =
      [
        base_url: "https://api.github.com",
        url: path,
        method: method,
        auth: {:bearer, token},
        headers: [
          {"accept", "application/vnd.github+json"},
          {"x-github-api-version", "2022-11-28"}
        ],
        max_retries: 2,
        retry_delay: 1_000,
        receive_timeout: 30_000
      ] ++ opts

    req_opts = if json_opt, do: Keyword.put(req_opts, :json, json_opt), else: req_opts
    req_opts = if raw, do: Keyword.put(req_opts, :decode_body, false), else: req_opts

    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        message =
          case body do
            %{"message" => msg} -> msg
            msg when is_binary(msg) -> msg
            _ -> "HTTP #{status}"
          end

        {:error, "GitHub API error (#{status}): #{message}"}

      {:error, reason} ->
        {:error, "GitHub request failed: #{inspect(reason)}"}
    end
  end
end
