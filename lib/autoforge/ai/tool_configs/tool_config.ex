defmodule Autoforge.Ai.ToolConfigs.ToolConfig do
  use Ash.Type.NewType,
    subtype_of: :union,
    constraints: [
      types: [
        google_workspace: [
          type: Autoforge.Ai.ToolConfigs.GoogleWorkspaceConfig,
          tag: :type,
          tag_value: "google_workspace"
        ]
      ]
    ]
end
