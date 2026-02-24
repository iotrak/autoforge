defmodule Autoforge.Projects.ProjectUserGroup do
  use Ash.Resource,
    otp_app: :autoforge,
    domain: Autoforge.Projects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "project_user_groups"
    repo Autoforge.Repo

    references do
      reference :project, on_delete: :delete
      reference :user_group, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy, update: :*]

    create :create do
      accept [:project_id, :user_group_id]
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
    belongs_to :project, Autoforge.Projects.Project do
      primary_key? true
      allow_nil? false
    end

    belongs_to :user_group, Autoforge.Accounts.UserGroup do
      primary_key? true
      allow_nil? false
    end
  end
end
