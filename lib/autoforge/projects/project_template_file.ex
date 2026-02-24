defmodule Autoforge.Projects.ProjectTemplateFile do
  use Ash.Resource,
    otp_app: :autoforge,
    domain: Autoforge.Projects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "project_template_files"
    repo Autoforge.Repo

    references do
      reference :project_template, on_delete: :delete
      reference :parent, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :name,
        :content,
        :is_directory,
        :sort_order,
        :project_template_id,
        :parent_id
      ]
    end

    update :update do
      accept [:name, :content, :is_directory, :sort_order, :parent_id]
      require_atomic? false
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
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints max_length: 255
    end

    attribute :content, :string do
      allow_nil? true
      public? true
    end

    attribute :is_directory, :boolean do
      allow_nil? false
      public? true
      default false
    end

    attribute :sort_order, :integer do
      allow_nil? false
      public? true
      default 0
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project_template, Autoforge.Projects.ProjectTemplate do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :parent, Autoforge.Projects.ProjectTemplateFile do
      allow_nil? true
      attribute_writable? true
    end

    has_many :children, Autoforge.Projects.ProjectTemplateFile do
      destination_attribute :parent_id
    end
  end
end
