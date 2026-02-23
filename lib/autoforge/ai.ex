defmodule Autoforge.Ai do
  use Ash.Domain, otp_app: :autoforge, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Autoforge.Ai.Bot
    resource Autoforge.Ai.BotUserGroup
    resource Autoforge.Ai.Tool
    resource Autoforge.Ai.BotTool
    resource Autoforge.Ai.UserGroupTool
  end
end
