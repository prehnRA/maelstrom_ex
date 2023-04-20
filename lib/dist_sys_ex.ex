defmodule DistSysEx do
  @moduledoc """
  Documentation for `DistSysEx`.
  """
  def take_input_forever(pid) do
    stream = IO.stream()
    Task.async(fn ->
      Enum.each(stream, fn line ->
        message = Jason.decode!(line)
        log("Received: #{inspect(message)}")

        GenServer.cast(pid, message)
      end)
    end)
  end

  def log(log) do
    GenServer.cast(self(), {:log, log})
  end

  def send_message(dest, body) do
    GenServer.cast(self(), {:send_message, dest, body})
  end

  def send_reply(replyee, in_reply_to, body) do
    send_message(replyee, Map.put(body, :in_reply_to, in_reply_to))
  end

  def send_error(replyee, in_reply_to, error_code, error_text) do
    body =
      %{
        "type" => "error",
        "code" => error_code,
        "text" => error_text
      }

    send_reply(replyee, in_reply_to, body)
  end

  defmacro __using__(_opts \\ []) do
    quote do
      use GenServer

      require Logger
      import DistSysEx

      unquote(setup_cast_handlers())
    end
  end

  def setup_cast_handlers() do
    quote do
      def run_forever(initial_state \\ %{}) do
        {:ok, pid} = GenServer.start_link(__MODULE__, initial_state)
        take_input_forever(pid) |> Task.await(:infinity)
      end

      @impl true
      def init(inner_state \\ %{}) do
        {:ok, {%{msg_id: 1}, inner_state}}
      end

      @impl true
      def handle_cast(%{
        "src" => src,
        "body" => %{
          "type" => "init",
          "msg_id" => msg_id,
          "node_id" => node_id,
          "node_ids" => node_ids
        }}, {node, inner_state}) do

        new_node_state = Map.merge(node, %{node_id: node_id, node_ids: node_ids})

        send_reply(src, msg_id, %{"type" => "init_ok"})
        {:noreply, {new_node_state, inner_state}}
      end

      @impl true
      def handle_cast(%{
        "src" => src,
        "dest" => dest,
        "body" => %{"msg_id" => msg_id} = body
      }, {me, inner_state}) do
        case handle_message(src, dest, body, inner_state) do
          {:reply, body, new_inner_state} ->
            send_reply(src, msg_id, body)
            {:noreply, {me, new_inner_state}}

          {:noreply, new_inner_state} ->
            {:noreply, {me, new_inner_state}}

          {:error, error_code, error_text, new_inner_state} ->
            send_error(src, msg_id, error_code, error_text)
            {:noreply, {me, new_inner_state}}
        end
      end

      def handle_cast({:send_message, dest, body}, {%{node_id: src, msg_id: msg_id} = node_state, inner_state}) do
         message = %{
          "src" => src,
          "dest" => dest,
          "body" => Map.put(body, "msg_id", msg_id)
        }
        json = Jason.encode!(message)

        IO.puts(json)

        new_node_state = Map.put(node_state, :msg_id, msg_id)

        {:noreply, {new_node_state, inner_state}}
      end

      def handle_cast({:log, log}, state) do
        IO.warn(log)

        {:noreply, state}
      end

      def handle_cast(other, _state) do
        raise "Unexpected message format: #{inspect(other)}"
      end
    end
  end
end
