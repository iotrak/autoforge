defmodule Autoforge.Mcp.Tools.AskBot do
  @moduledoc "Send a message to a bot and receive its response"

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  require Ash.Query

  @response_timeout :timer.seconds(120)

  schema do
    field :bot_name, {:required, :string}, description: "The name of the bot to message"
    field :message, {:required, :string}, description: "The message to send to the bot"
  end

  @impl true
  def execute(%{bot_name: bot_name, message: message}, frame) do
    user = frame.assigns.current_user

    with {:ok, bot} <- find_bot(bot_name, user),
         {:ok, conversation, frame} <- get_or_create_conversation(bot, user, frame),
         {:ok, _message} <- send_message(conversation, message, user),
         {:ok, response_text} <- await_response(conversation.id, bot.id) do
      {:reply, Response.text(Response.tool(), response_text), frame}
    else
      {:error, :bot_not_found} ->
        {:reply, Response.error(Response.tool(), "Bot '#{bot_name}' not found"), frame}

      {:error, :timeout} ->
        {:reply, Response.error(Response.tool(), "Bot did not respond within timeout"), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Error: #{inspect(reason)}"), frame}
    end
  end

  defp find_bot(name, user) do
    case Autoforge.Ai.Bot
         |> Ash.Query.filter(name == ^name)
         |> Ash.read_one(actor: user) do
      {:ok, nil} -> {:error, :bot_not_found}
      {:ok, bot} -> {:ok, bot}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_or_create_conversation(bot, user, frame) do
    conversations = Map.get(frame.assigns, :conversations, %{})

    case Map.get(conversations, bot.id) do
      nil ->
        conversation =
          Autoforge.Chat.Conversation
          |> Ash.Changeset.for_create(:create, %{subject: "MCP: #{bot.name}", bot_ids: [bot.id]},
            actor: user
          )
          |> Ash.create!()

        conversations = Map.put(conversations, bot.id, conversation.id)
        frame = assign(frame, :conversations, conversations)
        {:ok, conversation, frame}

      conversation_id ->
        case Ash.get(Autoforge.Chat.Conversation, conversation_id, actor: user) do
          {:ok, conversation} ->
            {:ok, conversation, frame}

          {:error, _} ->
            # Conversation was deleted; create a new one
            conversations = Map.delete(conversations, bot.id)
            frame = assign(frame, :conversations, conversations)
            get_or_create_conversation(bot, user, frame)
        end
    end
  end

  defp send_message(conversation, body, user) do
    Autoforge.Chat.Message
    |> Ash.Changeset.for_create(
      :create,
      %{body: body, role: :user, conversation_id: conversation.id},
      actor: user
    )
    |> Ash.create()
  end

  defp await_response(conversation_id, bot_id) do
    topic = "conversation:#{conversation_id}"
    AutoforgeWeb.Endpoint.subscribe(topic)

    try do
      receive_loop(bot_id)
    after
      AutoforgeWeb.Endpoint.unsubscribe(topic)
    end
  end

  defp receive_loop(bot_id) do
    receive do
      %Phoenix.Socket.Broadcast{
        event: "create",
        payload: %Ash.Notifier.Notification{data: message}
      } ->
        if message.role == :bot and message.bot_id == bot_id do
          {:ok, message.body}
        else
          receive_loop(bot_id)
        end

      {:bot_thinking, ^bot_id, _thinking} ->
        receive_loop(bot_id)

      {:tool_invocations_saved, _message_id} ->
        receive_loop(bot_id)
    after
      @response_timeout -> {:error, :timeout}
    end
  end
end
