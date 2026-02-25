defmodule Autoforge.Ai.ToolConfigs.GoogleWorkspaceConfig do
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :google_service_account_config_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :delegate_email, :string do
      allow_nil? false
      public? true
    end
  end
end
