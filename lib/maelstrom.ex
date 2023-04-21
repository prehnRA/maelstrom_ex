defmodule Maelstrom do
  @moduledoc """
  Allows you to create servers which implement the [Maelstrom protocol](https://github.com/jepsen-io/maelstrom/blob/main/doc/protocol.md).

  [Maelstrom](https://github.com/jepsen-io/maelstrom) is a workbench for learning distributed systems by writing your own.

  # Usage

  To implement a server:

  1. Create a module and `use Maelstrom`
  2. Implement one or more `handle_message` heads.
  3. Call `MyModule.run_forever()`.

  I recommend you do this in a .exs script. Example:

  ```
  defmodule Echo do
    use Maelstrom

    def handle_message(_src, _dest, %{"echo" => echo}, state, _) do
      {:reply, %{"type" => "echo_ok", "echo" => echo}, state}
    end
  end

  Echo.run_forever()
  ```

  You could then run this with `mix run` e.g. `mix run echo.exs`.

  > #### Tip {: .tip}
  > Maelstrom expects a single binary with no arguments to call for testing.
  > In order to accomplish this, wrap your mix run command in a shell script (see [demos](https://github.com/prehnRA/maelstrom_ex/tree/main/demo) for examples).

  # Examples

  For more examples, see [demos](https://github.com/prehnRA/maelstrom_ex/tree/main/demo).
  """

  @type node_id() :: String.t()
  @type msg_id() :: non_neg_integer()
  @type error_code() :: non_neg_integer()
  @type body() :: Map
  @type state() :: Map
  @type node_state() :: Map
  @type handler_result() :: {:reply, body(), state()} | {:noreply, state()} | {:error, non_neg_integer(), String.t(), state()}
  @type rpc_callback() :: (body(), body(), state() -> handler_result())

  @doc "Docs on a callback?"
  @callback handle_message(node_id(), node_id(), body(), state(), node_state()) :: handler_result()

  @doc """
  Run the server forever and prevent the script from exiting. Handles IO to and
  from your server node. You should invoke this directly on your server module
  instead of calling it on `Maelstrom` e.g. `MyModule.run_forever()`. This function
  is defined automatically when you `use Maelstrom`.
  """
  @spec run_forever(state()) :: :ok
  def run_forever(_initial_state \\ %{}) do
    # Stub for documentation
    raise "Call this function directly on your server module e.g. MyModule.run_forever()."
  end

  @doc false
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

  @doc "Logs an error to :stderr in the way that Maelstrom expects."
  @spec log(String.t(), atom()) :: :ok
  def log(log, adapter \\ GenServer) do
    adapter.cast(self(), {:log, log})
  end

  @doc """
  Send an RPC-style message with the body `body` to `dest`. `callback` is a function
  that will be invoked if and when `dest` replies to the message. The arguments to callback are:

  1. The body of the original message.
  2. The body of the reply.
  3. The state of your server.

  The callback should reply with a valid handler response:

  1. `{:reply, reply_body, new_server_state}`
  2. `{:noreply, new_server_state}`
  3. `{:error, error_code, error_message, new_server_state}`
  """
  @spec send_rpc(node_id(), body(), rpc_callback(), atom()) :: :ok
  def send_rpc(dest, body, callback, adapter \\ GenServer) do
    adapter.cast(self(), {:send_rpc, dest, body, callback})
  end

  @doc """
  Send a message with the body `body` to `dest`.
  """
  @spec send_message(node_id(), body(), atom()) :: :ok
  def send_message(dest, body, adapter \\ GenServer) do
    adapter.cast(self(), {:send_message, dest, body})
  end

  @doc """
  Send a reply to `replyee` replying to the message with id `in_reply_to`. Include the body `body`.
  """
  @spec send_reply(node_id(), msg_id(), body(), atom()) :: :ok
  def send_reply(replyee, in_reply_to, body, adapter \\ GenServer) do
    send_message(replyee, Map.put(body, "in_reply_to", in_reply_to), adapter)
  end

  @doc """
  Send an error message to `replyee` in reply to the message indentified by `in_reply_to`. The error
  message will include the error code `error_code` (see
  [the Maelstrom docs](https://github.com/jepsen-io/maelstrom/blob/main/doc/protocol.md#errors) for
  a list of codes) and a string message `error_text`.
  """
  @spec send_error(node_id(), msg_id(), error_code(), String.t(), atom()) :: :ok
  def send_error(replyee, in_reply_to, error_code, error_text, adapter \\ GenServer) do
    body =
      %{
        "type" => "error",
        "code" => error_code,
        "text" => error_text
      }

    send_reply(replyee, in_reply_to, body, adapter)
  end

  defmacro __using__(_opts \\ []) do
    quote do
      use GenServer

      require Logger
      import Maelstrom

      unquote(setup_cast_handlers())
    end
  end

  @doc false
  def default_node_state do
    %{msg_id: 1, rpcs: %{}}
  end

  @doc false
  def setup_cast_handlers() do
    quote do
      def run_forever(initial_state \\ %{}) do
        {:ok, pid} = GenServer.start_link(__MODULE__, initial_state)
        take_input_forever(pid) |> Task.await(:infinity)
      end

      @impl true
      def init(inner_state \\ %{}) do
        {:ok, {Maelstrom.default_node_state(), inner_state}}
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
