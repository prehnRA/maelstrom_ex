defmodule Kafka do
  use Maelstrom

  def handle_message(_src, _dest, %{"type" => "send", "key" => key, "msg" => msg}, %{logs: logs} = state, _node_state) do
    {offset, list} =
      logs
      |> Map.get(key, [])
      |> case do
        [] ->
          {1000, [{1000, msg}]}
        [{hd_offset, _}|_] = other ->
          {hd_offset + 1, [{hd_offset + 1, msg}|other]}
        end

    logs = Map.put(logs, key, list)
    {:reply, %{"type" => "send_ok", "offset" => offset}, %{state|logs: logs}}
  end

  def handle_message(_src, _dest, %{"type" => "poll", "offsets" => offsets}, %{logs: logs} = state, _node_state) do
    messages =
      offsets
      |> Enum.map(fn {key, offset} ->
        filtered_log =
          logs
          |> Map.get(key, [])
          |> Enum.filter(fn {log_offset, _value} ->
            log_offset >= offset
          end)
          |> Enum.reverse()
          |> Enum.map(fn {offset, value} ->
            [offset, value]
          end)

        {key, filtered_log}
      end)
      |> Enum.into(%{})

    {:reply, %{"type" => "poll_ok", "msgs" => messages}, state}
  end

  def handle_message(_src, _dest, %{"type" => "commit_offsets", "offsets" => offset}, %{committed_offsets: committed_offsets} = state, _node_state) do
    committed_offsets = Map.merge(committed_offsets, offset)

    {:reply, %{"type" => "commit_offsets_ok"}, %{state|committed_offsets: committed_offsets}}
  end

  def handle_message(_src, _dest, %{"type" => "list_committed_offsets", "keys" => keys}, %{committed_offsets: committed_offsets} = state, _node_state) do
    offsets = Map.take(committed_offsets, keys)

    {:reply, %{"type" => "list_committed_offsets_ok", "offsets" => offsets}, state}
  end
end

Kafka.run_forever(%{logs: %{}, committed_offsets: %{}})
