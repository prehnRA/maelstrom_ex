defmodule Broadcast do
  use Maelstrom

  def handle_message(
    src,
    dest,
    %{"type" => "add", "delta" => delta, "msg_id" => msg_id} = body,
    %{seen_msgs: seen_msgs} = state,
    %{node_ids: node_ids}) do

      node_ids
      |> Enum.each(fn dest ->
        send_rpc(dest, body, fn _original_body, _reply_body, inner_state ->
          log("Got RPC reply")

          {:noreply, inner_state}
        end)
      end)

    state =
      state
      |> Map.put(:seen_msgs, MapSet.put(seen_msgs, {msg_id, delta}))

    {:reply, %{"type" => "add_ok"}, state}
  end

  def handle_message(_src, _dest, %{"type" => "read"}, %{seen_msgs: seen_msgs} = state, _) do
    value =
      seen_msgs
      |> MapSet.to_list()
      |> Enum.reduce(0, fn {_, delta}, sum ->
        sum + delta
      end)
    {:reply, %{"type" => "read_ok", "value" => value}, state}
  end
end

Broadcast.run_forever(%{seen_msgs: MapSet.new()})
