defmodule AutoforgeWeb.Plugs.MCPAuth do
  @moduledoc """
  Extracts the Bearer token from the Authorization header and authenticates
  the user via the API key strategy. Sets `:current_user` in conn assigns
  so it flows into the Hermes MCP frame.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> api_key] <- get_req_header(conn, "authorization"),
         {:ok, user} <- sign_in_with_api_key(api_key) do
      assign(conn, :current_user, user)
    else
      _ -> assign(conn, :current_user, nil)
    end
  end

  defp sign_in_with_api_key(api_key) do
    strategy = AshAuthentication.Info.strategy!(Autoforge.Accounts.User, :api_key)
    AshAuthentication.Strategy.action(strategy, :sign_in, %{api_key: api_key})
  end
end
