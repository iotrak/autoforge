defmodule Autoforge.Mcp.Server do
  @moduledoc """
  MCP server exposing bot interaction tools over StreamableHTTP.
  Authenticates via Bearer API key in the Authorization header.
  """

  use Hermes.Server,
    name: "autoforge",
    version: "1.0.0",
    capabilities: [:tools]

  require Logger

  component(Autoforge.Mcp.Tools.ListBots)
  component(Autoforge.Mcp.Tools.AskBot)

  @impl true
  def init(_client_info, frame) do
    case frame.assigns[:current_user] do
      nil ->
        Logger.warning("MCP connection rejected: no valid API key")
        {:error, %Hermes.MCP.Error{code: -32_000, message: "Unauthorized"}, frame}

      user ->
        Logger.info("MCP client authenticated as #{user.email}")
        {:ok, assign(frame, :current_user, user)}
    end
  end
end
