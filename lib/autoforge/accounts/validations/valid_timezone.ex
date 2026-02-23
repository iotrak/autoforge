defmodule Autoforge.Accounts.Validations.ValidTimezone do
  use Ash.Resource.Validation

  @tz_extra_mod TzExtra

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :timezone) do
      nil ->
        :ok

      timezone ->
        if @tz_extra_mod.time_zone_id_exists?(timezone) do
          :ok
        else
          {:error, field: :timezone, message: "is not a valid timezone"}
        end
    end
  end
end
