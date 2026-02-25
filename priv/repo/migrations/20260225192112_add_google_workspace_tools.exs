defmodule Autoforge.Repo.Migrations.AddGoogleWorkspaceTools do
  use Ecto.Migration

  @google_workspace_tools [
    # Gmail
    {"gmail_list_messages",
     "List Gmail messages matching a search query. Returns message IDs and thread IDs."},
    {"gmail_get_message",
     "Get the full content of a Gmail message by ID, including headers, body, and labels."},
    {"gmail_send_message", "Send an email via Gmail."},
    {"gmail_modify_labels", "Add or remove labels on a Gmail message."},
    {"gmail_list_labels", "List all Gmail labels for the delegated user''s mailbox."},
    # Calendar
    {"calendar_list_calendars", "List all calendars the delegated user has access to."},
    {"calendar_list_events", "List events from a Google Calendar."},
    {"calendar_get_event", "Get details of a specific calendar event."},
    {"calendar_create_event", "Create a new event on a Google Calendar."},
    {"calendar_update_event", "Update an existing calendar event."},
    {"calendar_delete_event", "Delete a calendar event."},
    {"calendar_freebusy_query",
     "Query free/busy information for one or more calendars within a time range."},
    # Drive
    {"drive_list_files", "List files in Google Drive with optional search query."},
    {"drive_get_file", "Get metadata for a Google Drive file."},
    {"drive_download_file", "Download the content of a Google Drive file."},
    {"drive_upload_file", "Upload a file to Google Drive."},
    {"drive_update_file", "Update a Google Drive file''s metadata."},
    {"drive_copy_file", "Create a copy of a Google Drive file."},
    {"drive_list_shared_drives", "List shared drives the delegated user has access to."},
    # Directory
    {"directory_list_users", "List users in a Google Workspace domain."},
    {"directory_get_user", "Get details of a specific user in the Google Workspace directory."}
  ]

  def up do
    for {name, description} <- @google_workspace_tools do
      execute """
      INSERT INTO tools (id, name, description, inserted_at, updated_at)
      VALUES (gen_random_uuid(), '#{name}', '#{description}', now(), now())
      ON CONFLICT (name) DO NOTHING
      """
    end
  end

  def down do
    names =
      @google_workspace_tools
      |> Enum.map(fn {name, _} -> "'#{name}'" end)
      |> Enum.join(", ")

    execute "DELETE FROM tools WHERE name IN (#{names})"
  end
end
