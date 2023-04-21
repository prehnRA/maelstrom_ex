defmodule UniqueID do
  use Maelstrom

  def handle_message(_src, _dest, %{}, state, _) do
    {:reply, %{"type" => "generate_ok", "id" => Ecto.UUID.generate()}, state}
  end
end

UniqueID.run_forever()
