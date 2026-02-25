defmodule Autoforge.Google.Auth do
  @moduledoc """
  Thin wrapper around Goth for fetching Google OAuth2 access tokens
  from service account credentials stored in the database.
  """

  @default_scopes ["https://www.googleapis.com/auth/devstorage.read_write"]

  @doc """
  Fetches an access token for the given service account config using the default GCS scope.

  Returns `{:ok, token_string}` or `{:error, reason}`.
  """
  def get_access_token(service_account_config) do
    get_access_token(service_account_config, @default_scopes)
  end

  @doc """
  Fetches an access token for the given service account config with custom scopes.

  Returns `{:ok, token_string}` or `{:error, reason}`.
  """
  def get_access_token(service_account_config, scopes) do
    with {:ok, credentials} <- decode_credentials(service_account_config) do
      source = {:service_account, credentials, scopes: scopes}

      case Goth.Token.fetch(%{source: source}) do
        {:ok, %{token: token}} -> {:ok, token}
        {:error, reason} -> {:error, "Token fetch failed: #{inspect(reason)}"}
      end
    end
  end

  defp decode_credentials(%{service_account_json: json}) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, credentials} -> {:ok, credentials}
      {:error, _} -> {:error, "Invalid service account JSON"}
    end
  end

  defp decode_credentials(_), do: {:error, "Missing service account JSON"}
end
