defmodule AOS.Runtime.CommandRunner do
  @moduledoc """
  Thin shell command adapter for runtime services and MCP tools.
  """

  @default_timeout_ms 30_000
  @default_output_limit 64_000

  def run(command, args \\ [], opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    output_limit = Keyword.get(opts, :output_limit, @default_output_limit)

    task =
      Task.async(fn ->
        try do
          command
          |> System.cmd(args, system_cmd_opts(opts, output_limit))
          |> normalize_result(output_limit)
        rescue
          error ->
            %{
              output: Exception.message(error),
              exit_code: 127,
              timed_out?: false,
              truncated?: false
            }
        catch
          :exit, reason ->
            %{output: inspect(reason), exit_code: 127, timed_out?: false, truncated?: false}
        end
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} ->
        {:ok, result}

      nil ->
        {:ok,
         %{output: "Command timed out after #{timeout_ms}ms", exit_code: 124, timed_out?: true}}
    end
  rescue
    error -> {:error, error}
  end

  defp system_cmd_opts(opts, output_limit) do
    opts
    |> Keyword.drop([:timeout_ms, :output_limit])
    |> Keyword.put_new(:stderr_to_stdout, true)
    |> Keyword.put(:into, limit_collector(output_limit))
  end

  defp normalize_result({output, code}, output_limit) do
    output = IO.iodata_to_binary(output)
    truncated? = byte_size(output) > output_limit

    output =
      if truncated? do
        binary_part(output, 0, output_limit) <> "\n[output truncated at #{output_limit} bytes]"
      else
        output
      end

    %{output: output, exit_code: code, timed_out?: false, truncated?: truncated?}
  end

  defp limit_collector(output_limit),
    do: struct(AOS.Runtime.CommandRunner.OutputCollector, limit: output_limit)
end

defmodule AOS.Runtime.CommandRunner.OutputCollector do
  @moduledoc false

  defstruct [:limit]

  defimpl Collectable do
    def into(%{limit: limit}) do
      collector = fn
        {chunks, remaining}, {:cont, chunk} when remaining > 0 ->
          collect_chunk(chunks, remaining, chunk)

        {chunks, remaining}, {:cont, _chunk} ->
          {chunks, remaining}

        {chunks, _remaining}, :done ->
          chunks |> Enum.reverse() |> IO.iodata_to_binary()

        _state, :halt ->
          :ok
      end

      {{[], limit}, collector}
    end

    defp collect_chunk(chunks, remaining, chunk) do
      binary = IO.iodata_to_binary(chunk)
      size = byte_size(binary)

      if size <= remaining do
        {[binary | chunks], remaining - size}
      else
        {[binary_part(binary, 0, remaining) | chunks], 0}
      end
    end
  end
end
