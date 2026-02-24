defmodule AutoforgeWeb.TerminalChannel do
  use AutoforgeWeb, :channel

  alias Autoforge.Projects.{Project, Terminal}

  require Ash.Query

  @impl true
  def join("terminal:" <> project_id, _payload, socket) do
    user_id = socket.assigns.user_id

    user =
      Autoforge.Accounts.User
      |> Ash.Query.filter(id == ^user_id)
      |> Ash.read_one!(authorize?: false)

    project =
      Project
      |> Ash.Query.filter(id == ^project_id)
      |> Ash.read_one!(actor: user)

    cond do
      is_nil(project) ->
        {:error, %{reason: "not_found"}}

      project.state != :running ->
        {:error, %{reason: "not_running"}}

      true ->
        {:ok, terminal_pid} =
          Terminal.start_link(project: project, channel_pid: self())

        {:ok, assign(socket, :terminal_pid, terminal_pid)}
    end
  end

  @impl true
  def handle_in("input", %{"data" => data}, socket) do
    Terminal.send_input(socket.assigns.terminal_pid, data)
    {:noreply, socket}
  end

  def handle_in("resize", %{"cols" => cols, "rows" => rows}, socket) do
    Terminal.resize(socket.assigns.terminal_pid, cols, rows)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:terminal_output, data}, socket) do
    push(socket, "output", %{data: data})
    {:noreply, socket}
  end

  def handle_info(:terminal_closed, socket) do
    push(socket, "output", %{data: "\r\n\x1b[31mTerminal session ended.\x1b[0m\r\n"})
    {:stop, :normal, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:terminal_pid] && Process.alive?(socket.assigns.terminal_pid) do
      GenServer.stop(socket.assigns.terminal_pid)
    end

    :ok
  end
end
