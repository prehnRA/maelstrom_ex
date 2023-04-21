defmodule ExampleServer do
  use Maelstrom

  def handle_message(src, dest, body, _state, _node_state) do
    {:noreply, %{src: src, dest: dest, body: body}}
  end
end

defmodule MaelstromTest do
  use ExUnit.Case, async: true
  doctest Maelstrom

  import Maelstrom

  defmodule FauxGenServer do
    def cast(pid, message), do: {pid, message}
  end

  test "log/2" do
    assert log("Hello", FauxGenServer) == {self(), {:log, "Hello"}}
  end

  test "send_rpc/4" do
    callback = fn _, _, _-> nil end

    assert send_rpc("n0", %{"type" => "test"}, callback, FauxGenServer) == {
      self(),
      {:send_rpc, "n0", %{"type" => "test"}, callback}}
  end

  test "send_message/3" do
    assert send_message("n0", %{"type" => "test"}, FauxGenServer) == {
      self(),
      {:send_message, "n0", %{"type" => "test"}}
    }
  end

  test "send_reply/4" do
    assert send_reply("n0", 123, %{"type" => "test"}, FauxGenServer) == {
      self(),
      {
        :send_message,
        "n0",
        %{
          "type" => "test",
          "in_reply_to" => 123
        }
      }
    }
  end

  test "send_error/5" do
    assert send_error("n0", 123, 456, "Oops", FauxGenServer) == {
      self(),
      {
        :send_message,
        "n0",
        %{
          "type" => "error",
          "code" => 456,
          "text" => "Oops",
          "in_reply_to" => 123
        }
      }
    }
  end

  describe "an example server" do
    import ExampleServer
    import ExUnit.CaptureIO

    test "init/1" do
      assert init(%{test: 123}) == {
        :ok,
        {
          Maelstrom.default_node_state(),
          %{test: 123}
        }
      }
    end

    test "handle_cast/2 with init message" do
      msg = %{
        "src" => "c0",
        "dest" => "n0",
        "body" => %{
          "type" => "init",
          "msg_id" => 1234,
          "node_id" => "n0",
          "node_ids" => ["n0", "n1"]
        }
      }

      assert handle_cast(msg, {%{node: true}, %{inner: true}}) == {
        :noreply,
        {
          %{node: true, node_id: "n0", node_ids: ["n0", "n1"]},
          %{inner: true}
        }
      }
    end

    test "handle_cast/2 with a reply" do
      orig_msg_body = %{"type" => "hello"}
      reply_body = %{"in_reply_to" => 123, "msg_id" => 1}

      callback =
        fn ^orig_msg_body, ^reply_body, _state ->
          {:noreply, %{called_back: true}}
        end

      node_state = %{
        rpcs: %{
          123 => {orig_msg_body, callback}
        },
        node_state: true
      }

      msg = %{
        "src" => "n1",
        "body" => reply_body
      }

      assert {
        :noreply,
        {
          %{node_state: true},
          %{called_back: true}
        }
      } = handle_cast(msg, {node_state, %{}})
    end

    test "handle other protocol messages" do
      msg = %{
        "src" => "n1",
        "dest" => "n0",
        "body" => %{
          "msg_id" => 123
        }
      }

      assert handle_cast(msg, {%{node: true}, %{}}) == {
        :noreply,
        {
          %{node: true},
          %{
            src: "n1",
            dest: "n0",
            body: %{"msg_id" => 123}
          }
        }
      }
    end

    test "handle_cast with a send_message" do
      signal = {
        :send_message,
        "n1",
        %{"type" => "test"}
      }

      scenario = fn ->
        assert handle_cast(signal, {%{msg_id: 0, node_id: "n343"}, %{inner: true}}) == {
          :noreply,
          {
            %{msg_id: 1, node_id: "n343"},
            %{inner: true}
          }
        }
      end


      output =
        capture_io(:stdio, scenario)

      output_stderr =
        capture_io(:stderr, scenario)

      assert Jason.decode!(output) == %{
        "src" => "n343",
        "dest" => "n1",
        "body" => %{
          "type" => "test",
          "msg_id" => 0
        }
      }

      assert output_stderr == ""
    end

    test "handle_cast with a log" do
      signal = {:log, "oopsy"}

      scenario = fn ->
        assert handle_cast(signal, {%{msg_id: 0, node_id: "n343"}, %{inner: true}}) == {
          :noreply,
          {
            %{msg_id: 0, node_id: "n343"},
            %{inner: true}
          }
        }
      end


      output =
        capture_io(:stdio, scenario)

      output_stderr =
        capture_io(:stderr, scenario)

      assert output == ""

      assert output_stderr =~ "oopsy"
    end
  end
end
