defmodule Autoforge.Accounts.Validations.ValidProvider do
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :provider) do
      nil ->
        :ok

      provider ->
        valid_ids = LLMDB.providers() |> Enum.map(& &1.id)

        if provider in valid_ids do
          :ok
        else
          {:error, field: :provider, message: "is not a valid LLM provider"}
        end
    end
  end
end
