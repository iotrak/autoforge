defmodule Autoforge.Accounts.LlmProviderKey do
  use Ash.Resource,
    otp_app: :autoforge,
    domain: Autoforge.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshCloak]

  postgres do
    table "llm_provider_keys"
    repo Autoforge.Repo
  end

  cloak do
    vault(Autoforge.Vault)
    attributes([:value])
    decrypt_by_default([:value])
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :provider, :value]
      change relate_actor(:user)
    end

    update :update do
      accept [:name, :value]
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
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  validations do
    validate {Autoforge.Accounts.Validations.ValidProvider, []} do
      on [:create]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :atom do
      allow_nil? false
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints max_length: 255
    end

    attribute :value, :string do
      allow_nil? false
      public? true
      constraints max_length: 1024
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Autoforge.Accounts.User do
      allow_nil? false
      attribute_writable? false
    end
  end

  identities do
    identity :unique_provider_per_user, [:user_id, :provider]
  end
end
