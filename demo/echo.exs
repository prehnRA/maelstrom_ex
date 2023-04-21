defmodule Echo do
  use Maelstrom

  def handle_message(_src, _dest, %{"echo" => echo}, state, _) do
    {:reply, %{"type" => "echo_ok", "echo" => echo}, state}
  end
end

Echo.run_forever()
