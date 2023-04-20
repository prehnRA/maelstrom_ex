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

  def send_rpc(dest, body, callback) do
    GenServer.cast(self(), {:send_rpc, dest, body, callback})
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
        {:ok, {%{msg_id: 1, rpcs: %{}}, inner_state}}
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

      def handle_cast(%{
        "src" => src,
        "body" => %{
          "in_reply_to" => msg_id
        } = reply_body} = msg, {%{rpcs: rpcs} = node_state, inner_state} = state) do

        {original_body, callback} = Map.get(rpcs, msg_id, {nil, &warn_missing_rpc_callback/3})
        process_callback(callback.(original_body, reply_body, inner_state), msg, state)
      end

      @impl true
      def handle_cast(%{
        "src" => src,
        "dest" => dest,
        "body" => %{"msg_id" => msg_id} = body
      } = msg, {node_state, inner_state} = state) do
        process_callback(handle_message(src, dest, body, inner_state, node_state), msg, state)
      end

      def handle_cast({:send_rpc, dest, body, callback}, {%{rpcs: rpcs, msg_id: msg_id} = node_state, inner_state}) do

        {:noreply, {new_node_state, inner_state}} = handle_cast({:send_message, dest, body}, {node_state, inner_state})

        rpcs = Map.put(rpcs, msg_id, {body, callback})

        node_state = Map.put(node_state, :rpcs, rpcs)

        {:noreply, {node_state, inner_state}}
      end

      def handle_cast({:send_message, dest, body}, {%{node_id: src, msg_id: msg_id} = node_state, inner_state}) do
         message = %{
          "src" => src,
          "dest" => dest,
          "body" => Map.put_new(body, "msg_id", msg_id)
        }
        json = Jason.encode!(message)

        IO.puts(json)

        new_node_state = Map.put(node_state, :msg_id, msg_id + 1)

        {:noreply, {new_node_state, inner_state}}
      end

      def handle_cast({:log, log}, state) do
        IO.warn(log)

        {:noreply, state}
      end

      def handle_cast(other, _state) do
        raise "Unexpected message format: #{inspect(other)}"
      end

      defp process_callback(result, %{
        "src" => src,
        "body" => %{"msg_id" => msg_id} = body
      }, {node_state, _}) do
        case result do
          {:reply, body, new_inner_state} ->
            send_reply(src, msg_id, body)
            {:noreply, {node_state, new_inner_state}}

          {:noreply, new_inner_state} ->
            {:noreply, {node_state, new_inner_state}}

          {:error, error_code, error_text, new_inner_state} ->
            send_error(src, msg_id, error_code, error_text)
            {:noreply, {node_state, new_inner_state}}
        end
      end

      defp warn_missing_rpc_callback(_message_body, reply_body, inner_state) do
        IO.warn("Reply for unknown RPC: reply_body=#{inspect(reply_body)}")

        {:noreply, inner_state}
      end
    end
  end
end
