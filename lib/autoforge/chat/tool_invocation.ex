defmodule Autoforge.Chat.ToolInvocation do
  use Ash.Resource,
    otp_app: :autoforge,
    domain: Autoforge.Chat,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "tool_invocations"
    repo Autoforge.Repo

    references do
      reference :message, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:tool_name, :arguments, :result, :status, :message_id]
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if actor_present()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :tool_name, :string do
      allow_nil? false
      public? true
    end

    attribute :arguments, :map do
      allow_nil? false
      public? true
    end

    attribute :result, :string do
      allow_nil? true
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:ok, :error]
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :message, Autoforge.Chat.Message do
      allow_nil? false
      attribute_writable? true
    end
  end
end
