defmodule Autoforge.Ai.ToolResolver do
  @moduledoc """
  Computes the set of tools a bot may use in a conversation.

  A tool is available only when it is assigned to the bot **and** to at
  least one user-group that a conversation participant belongs to
  (intersection model).
  """

  alias Autoforge.Accounts.UserGroupMembership
  alias Autoforge.Ai.ToolRegistry

  require Ash.Query

  @doc """
  Returns a list of `ReqLLM.Tool` structs that the bot is allowed to use
  given the conversation participants.

  The `bot` must be pre-loaded with `:tools`.
  """
  @spec resolve(%{tools: [%{name: String.t()}]}, [String.t()]) :: [ReqLLM.Tool.t()]
  def resolve(bot, participant_ids) do
    bot_tool_names = bot.tools |> Enum.map(& &1.name) |> MapSet.new()

    user_group_tool_names =
      UserGroupMembership
      |> Ash.Query.filter(user_id in ^participant_ids)
      |> Ash.Query.load(user_group: [:tools])
      |> Ash.read!(authorize?: false)
      |> Enum.flat_map(& &1.user_group.tools)
      |> Enum.map(& &1.name)
      |> MapSet.new()

    allowed = MapSet.intersection(bot_tool_names, user_group_tool_names) |> MapSet.to_list()
    ToolRegistry.get_many(allowed)
  end
end
