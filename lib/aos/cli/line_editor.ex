defmodule AOS.CLI.LineEditor do
  @moduledoc false

  @esc <<27>>
  @backspace 127
  @ctrl_c 3
  @ctrl_d 4

  def read_line(prompt, history \\ []) do
    initial_state = %{
      prompt: prompt,
      buffer: "",
      cursor: 0,
      history: Enum.uniq(history),
      history_index: nil,
      draft: ""
    }

    with {:ok, stty_state} <- stty("-g"),
         :ok <- set_raw_mode(),
         :ok <- render(initial_state) do
      result = loop(initial_state)
      restore_mode(stty_state)
      result
    else
      _ ->
        fallback_read(prompt)
    end
  end

  def apply_key(state, :up), do: history_up(state)
  def apply_key(state, :down), do: history_down(state)
  def apply_key(state, :left), do: %{state | cursor: max(state.cursor - 1, 0)}

  def apply_key(state, :right),
    do: %{state | cursor: min(state.cursor + 1, String.length(state.buffer))}

  def apply_key(state, :backspace), do: backspace(state)
  def apply_key(state, {:insert, text}), do: insert_text(state, text)

  def apply_key(state, _key), do: state

  defp loop(state) do
    case IO.binread(:stdio, 1) do
      :eof ->
        IO.write("\n")
        :eof

      <<@ctrl_c>> ->
        IO.write("^C\n")
        :interrupt

      <<@ctrl_d>> ->
        IO.write("\n")
        :eof

      <<@backspace>> ->
        state
        |> apply_key(:backspace)
        |> rerender_and_continue()

      <<"\r">> ->
        IO.write("\n")
        {:ok, state.buffer}

      <<"\n">> ->
        IO.write("\n")
        {:ok, state.buffer}

      @esc ->
        state
        |> handle_escape_sequence()
        |> rerender_and_continue()

      char ->
        state
        |> apply_key({:insert, char})
        |> rerender_and_continue()
    end
  end

  defp rerender_and_continue(state) do
    render(state)
    loop(state)
  end

  defp handle_escape_sequence(state) do
    case IO.binread(:stdio, 2) do
      <<"[A">> -> apply_key(state, :up)
      <<"[B">> -> apply_key(state, :down)
      <<"[C">> -> apply_key(state, :right)
      <<"[D">> -> apply_key(state, :left)
      _ -> state
    end
  end

  defp insert_text(state, text) do
    {left, right} = split_buffer(state.buffer, state.cursor)
    buffer = left <> text <> right
    %{state | buffer: buffer, cursor: state.cursor + String.length(text)}
  end

  defp backspace(%{cursor: 0} = state), do: state

  defp backspace(state) do
    {left, right} = split_buffer(state.buffer, state.cursor)
    left = String.slice(left, 0, String.length(left) - 1)
    %{state | buffer: left <> right, cursor: state.cursor - 1}
  end

  defp history_up(%{history: []} = state), do: state

  defp history_up(%{history_index: nil} = state) do
    index = length(state.history) - 1
    buffer = Enum.at(state.history, index, "")

    %{
      state
      | history_index: index,
        draft: state.buffer,
        buffer: buffer,
        cursor: String.length(buffer)
    }
  end

  defp history_up(%{history_index: 0} = state), do: state

  defp history_up(state) do
    index = state.history_index - 1
    buffer = Enum.at(state.history, index, "")
    %{state | history_index: index, buffer: buffer, cursor: String.length(buffer)}
  end

  defp history_down(%{history_index: nil} = state), do: state

  defp history_down(state) when state.history_index >= length(state.history) - 1 do
    %{state | history_index: nil, buffer: state.draft, cursor: String.length(state.draft)}
  end

  defp history_down(state) do
    index = state.history_index + 1
    buffer = Enum.at(state.history, index, "")
    %{state | history_index: index, buffer: buffer, cursor: String.length(buffer)}
  end

  defp split_buffer(buffer, cursor) do
    {String.slice(buffer, 0, cursor),
     String.slice(buffer, cursor, String.length(buffer) - cursor)}
  end

  defp render(state) do
    left_moves = String.length(state.buffer) - state.cursor

    IO.write("\r\e[2K")
    IO.write(state.prompt <> state.buffer)

    if left_moves > 0 do
      IO.write("\e[#{left_moves}D")
    end

    :ok
  end

  defp set_raw_mode do
    case stty("raw", "-echo") do
      {:ok, _} -> :ok
      _ -> {:error, :stty}
    end
  end

  defp restore_mode(stty_state) do
    _ = stty(stty_state)
    :ok
  end

  defp stty(arg1, arg2 \\ nil) do
    args = Enum.reject([arg1, arg2], &is_nil/1)

    case System.cmd("stty", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      _ -> {:error, :stty}
    end
  end

  defp fallback_read(prompt) do
    case IO.gets(prompt) do
      nil -> :eof
      input -> {:ok, String.trim_trailing(input, "\n")}
    end
  end
end
