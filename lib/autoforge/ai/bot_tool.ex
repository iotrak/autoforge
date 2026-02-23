defmodule Autoforge.Ai.BotTool do
  use Ash.Resource,
    otp_app: :autoforge,
    domain: Autoforge.Ai,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "bot_tools"
    repo Autoforge.Repo

    references do
      reference :bot, on_delete: :delete
      reference :tool, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy, update: :*]

    create :create do
      accept [:bot_id, :tool_id]
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type([:read, :create, :update, :destroy]) do
      authorize_if actor_present()
    end
  end

  attributes do
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :bot, Autoforge.Ai.Bot do
      primary_key? true
      allow_nil? false
    end

    belongs_to :tool, Autoforge.Ai.Tool do
      primary_key? true
      allow_nil? false
    end
  end
end
