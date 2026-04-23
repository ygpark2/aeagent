defmodule AOS.CLI.LineEditorTest do
  use ExUnit.Case, async: true

  alias AOS.CLI.LineEditor

  test "up arrow recalls prior history entries" do
    state = %{
      prompt: "agent> ",
      buffer: "",
      cursor: 0,
      history: ["first prompt", "second prompt"],
      history_index: nil,
      draft: ""
    }

    state = LineEditor.apply_key(state, :up)
    assert state.buffer == "second prompt"
    assert state.cursor == String.length("second prompt")

    state = LineEditor.apply_key(state, :up)
    assert state.buffer == "first prompt"
    assert state.cursor == String.length("first prompt")
  end

  test "down arrow returns to draft after browsing history" do
    state = %{
      prompt: "agent> ",
      buffer: "draft prompt",
      cursor: String.length("draft prompt"),
      history: ["first prompt", "second prompt"],
      history_index: nil,
      draft: ""
    }

    state = LineEditor.apply_key(state, :up)
    state = LineEditor.apply_key(state, :down)

    assert state.buffer == "draft prompt"
    assert state.history_index == nil
  end

  test "backspace removes the character before the cursor" do
    state = %{
      prompt: "agent> ",
      buffer: "hello",
      cursor: 5,
      history: [],
      history_index: nil,
      draft: ""
    }

    state = LineEditor.apply_key(state, :backspace)
    assert state.buffer == "hell"
    assert state.cursor == 4
  end
end
