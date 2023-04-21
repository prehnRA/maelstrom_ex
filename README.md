# Maelstrom

Allows you to create servers which implement the [Maelstrom protocol](https://github.com/jepsen-io/maelstrom/blob/main/doc/protocol.md).

[Maelstrom](https://github.com/jepsen-io/maelstrom) is a workbench for learning distributed systems by writing your own.

# Links

- Documentation: https://hexdocs.pm/maelstrom
- Package details on hex: https://hex.pm/maelstrom

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
