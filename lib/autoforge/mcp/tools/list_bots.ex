defmodule Autoforge.Mcp.Tools.ListBots do
  @moduledoc "Lists available bots with their names and descriptions"

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
  end

  @impl true
  def execute(_params, frame) do
    user = frame.assigns.current_user
    bots = Ash.read!(Autoforge.Ai.Bot, actor: user)

    result =
      Enum.map(bots, fn bot ->
        %{name: bot.name, description: bot.description}
      end)

    {:reply, Response.json(Response.tool(), result), frame}
  end
end
