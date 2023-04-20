defmodule Echo do
  use DistSysEx

  def handle_message(_src, _dest, %{"echo" => echo}, state, _) do
    {:reply, %{"type" => "echo_ok", "echo" => echo}, state}
  end
end

Echo.run_forever()
