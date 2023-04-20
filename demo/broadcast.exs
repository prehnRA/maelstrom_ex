defmodule Broadcast do
  use DistSysEx

  def handle_message(_src, dest, %{"type" => "topology", "topology" => topology}, state) do
    state =
      state
      |> Map.put(:myself, dest)
      |> Map.put(:topology, topology)
      |> Map.put_new_lazy(:seen_sets, fn ->
        topology
      |> Map.keys()
      |> Enum.map(fn node_id ->
        {node_id, MapSet.new()}
      end)
      |> Enum.into(%{})
      end)
    {:reply, %{"type" => "topology_ok"}, state}
  end

  def handle_message(src, dest, %{"type" => "broadcast", "message" => message}, %{seen_sets: seen_sets} = state) do
    IO.warn("state: #{inspect(state)}")
    IO.warn("src: #{inspect(src)}")
    IO.warn("dest: #{inspect(dest)}")
    src_seenset =
      if String.starts_with?(src, "c") do
        seen_sets |> Map.get(src)
      else
        seen_sets |> Map.get(src) |> MapSet.put(message)
      end
    dest_seenset = seen_sets |> Map.get(dest) |> MapSet.put(message)

    seen_sets =
      seen_sets
      |> Map.put(src, src_seenset)
      |> Map.put(dest, dest_seenset)

    state =
      state
      |> Map.get(:values)
      |> MapSet.put(message)
      |> then(&Map.put(state, :values, &1))
      |> Map.put(:seen_sets, seen_sets)

    gossip(state, message)

    {:reply, %{"type" => "broadcast_ok"}, state}
  end

  def handle_message(_src, _dest, %{"type" => "read"}, state) do
    {:reply, %{"type" => "read_ok", "messages" => MapSet.to_list(state.values)}, state}
  end

  def handle_message(_src, _dest, %{"type" => "broadcast_ok"}, state) do
    {:noreply, state}
  end

  def gossip(%{seen_sets: seen_sets, topology: topology, myself: myself}, message) do
    neighbors = Map.get(topology, myself)

    neighbors
    |> Enum.each(fn key ->
      seen_messages = Map.get(seen_sets, key)

      if !MapSet.member?(seen_messages, message) do
        send_message(key, %{"type" => "broadcast", "message" => message})
      end
    end)
  end
end

Broadcast.run_forever(%{topology: %{}, values: MapSet.new()})
