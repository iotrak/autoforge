defmodule Autoforge.Deployments.VmManagementOp do
  use Ash.Resource,
    otp_app: :autoforge,
    domain: Autoforge.Deployments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine, AshPaperTrail.Resource],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "vm_management_ops"
    repo Autoforge.Repo

    references do
      reference :vm_instance, on_delete: :delete
    end
  end

  state_machine do
    initial_states [:pending]
    default_initial_state :pending

    transitions do
      transition :start_running, from: :pending, to: :running
      transition :complete, from: :running, to: :completed
      transition :fail, from: [:pending, :running], to: :failed
    end
  end

  paper_trail do
    primary_key_type :uuid_v7
    change_tracking_mode :changes_only
    store_action_name? true
    reference_source? false
    ignore_attributes [:inserted_at, :updated_at]
    belongs_to_actor :user, Autoforge.Accounts.User, domain: Autoforge.Accounts
  end

  actions do
    defaults [:read]

    create :create do
      accept [:operation_type, :triggered_by, :vm_instance_id]
    end

    update :start_running do
      require_atomic? false
      change transition_state(:running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :complete do
      accept [:result]
      require_atomic? false
      change transition_state(:completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :fail do
      accept [:error_message, :result]
      require_atomic? false
      change transition_state(:failed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type([:read, :update, :destroy]) do
      authorize_if actor_present()
    end
  end

  pub_sub do
    module AutoforgeWeb.Endpoint
    prefix "vm_management_op"
    publish_all :update, ["updated", [:id, nil]]
  end

  attributes do
    uuid_primary_key :id

    attribute :operation_type, :atom do
      allow_nil? false
      public? true

      constraints one_of: [
                    :check_updates,
                    :apply_updates,
                    :setup_usg,
                    :restart,
                    :docker_cleanup,
                    :health_check
                  ]
    end

    attribute :result, :map do
      allow_nil? true
      public? true
    end

    attribute :error_message, :string do
      allow_nil? true
      public? true
    end

    attribute :started_at, :utc_datetime do
      allow_nil? true
      public? true
    end

    attribute :completed_at, :utc_datetime do
      allow_nil? true
      public? true
    end

    attribute :triggered_by, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:manual, :scheduled]
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :vm_instance, Autoforge.Deployments.VmInstance do
      allow_nil? false
      attribute_writable? true
    end
  end
end
