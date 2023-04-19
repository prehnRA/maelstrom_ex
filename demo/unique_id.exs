defmodule UniqueID do
  use DistSysEx

  def handle_message(_src, _dest, %{}, state) do
    {:reply, %{"type" => "generate_ok", "id" => Ecto.UUID.generate()}, state}
  end
end

UniqueID.run_forever()
