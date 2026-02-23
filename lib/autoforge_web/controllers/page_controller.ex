defmodule AutoforgeWeb.PageController do
  use AutoforgeWeb, :controller

  def home(conn, _params) do
    if conn.assigns[:current_user] do
      redirect(conn, to: ~p"/dashboard")
    else
      render(conn, :home, current_user: nil)
    end
  end
end
