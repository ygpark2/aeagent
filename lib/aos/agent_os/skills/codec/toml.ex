defmodule AOS.AgentOS.Skills.Codec.TOML do
  @moduledoc """
  Encodes and decodes skill metadata stored in `skill.toml`.
  """

  @default_priority 0

  def decode_skill_metadata(content) when is_binary(content) do
    content
    |> parse_simple_toml()
    |> flatten_skill_metadata()
  end

  def encode_skill_metadata(skill) do
    """
    [skill]
    name = "#{value(skill, :name)}"
    description = "#{escape_toml(value(skill, :description))}"
    tags = #{render_toml_array(value(skill, :tags))}
    triggers = #{render_toml_array(value(skill, :triggers))}
    capabilities = #{render_toml_array(value(skill, :capabilities))}
    is_active = #{if(value(skill, :is_active), do: "true", else: "false")}

    [execution]
    mode = "#{value(skill, :execution_mode) || "prompt_only"}"
    required_tools = #{render_toml_array(value(skill, :required_tools))}
    permissions = #{render_toml_array(value(skill, :permissions))}

    [selection]
    priority = #{value(skill, :priority) || @default_priority}
    """
    |> String.trim()
    |> Kernel.<>("\n")
  end

  defp flatten_skill_metadata(parsed) do
    skill = Map.get(parsed, "skill", %{})
    execution = Map.get(parsed, "execution", %{})
    selection = Map.get(parsed, "selection", %{})

    %{
      name: skill["name"],
      description: skill["description"],
      tags: skill["tags"],
      triggers: skill["triggers"],
      capabilities: skill["capabilities"],
      is_active: skill["is_active"],
      priority: selection["priority"],
      execution_mode: execution["mode"],
      permissions: execution["permissions"],
      required_tools: execution["required_tools"]
    }
  end

  defp parse_simple_toml(content) do
    content
    |> String.split("\n")
    |> Enum.reduce({%{}, nil}, fn raw_line, {acc, section} ->
      line =
        raw_line
        |> strip_comment()
        |> String.trim()

      cond do
        line == "" ->
          {acc, section}

        Regex.match?(~r/^\[[A-Za-z0-9_.-]+\]$/, line) ->
          [new_section] = Regex.run(~r/^\[([A-Za-z0-9_.-]+)\]$/, line, capture: :all_but_first)
          {Map.put_new(acc, new_section, %{}), new_section}

        String.contains?(line, "=") and is_binary(section) ->
          [key, value] = String.split(line, "=", parts: 2)
          parsed_value = parse_toml_value(String.trim(value))
          updated_section = Map.put(Map.get(acc, section, %{}), String.trim(key), parsed_value)
          {Map.put(acc, section, updated_section), section}

        true ->
          {acc, section}
      end
    end)
    |> elem(0)
  end

  defp strip_comment(line) do
    case String.split(line, "#", parts: 2) do
      [before | _] -> before
      [] -> line
    end
  end

  defp parse_toml_value(value) do
    trimmed = String.trim(value)

    cond do
      String.starts_with?(trimmed, "[") and String.ends_with?(trimmed, "]") ->
        trimmed
        |> String.trim_leading("[")
        |> String.trim_trailing("]")
        |> parse_toml_array()

      String.starts_with?(trimmed, "\"") and String.ends_with?(trimmed, "\"") ->
        trimmed
        |> String.trim_leading("\"")
        |> String.trim_trailing("\"")

      trimmed in ["true", "false"] ->
        trimmed == "true"

      Regex.match?(~r/^-?\d+$/, trimmed) ->
        String.to_integer(trimmed)

      true ->
        trimmed
    end
  end

  defp parse_toml_array(""), do: []

  defp parse_toml_array(content) do
    content
    |> String.split(",", trim: true)
    |> Enum.map(&parse_toml_value/1)
  end

  defp render_toml_array(nil), do: "[]"

  defp render_toml_array(value) do
    value
    |> normalize_list()
    |> Enum.map_join(", ", fn item -> "\"#{escape_toml(item)}\"" end)
    |> then(&"[#{&1}]")
  end

  defp normalize_list(nil), do: []
  defp normalize_list(value) when is_list(value), do: Enum.map(value, &to_string/1)

  defp normalize_list(value) when is_binary(value) do
    value
    |> String.split([",", "\n"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_list(value), do: [to_string(value)]

  defp escape_toml(nil), do: ""

  defp escape_toml(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end

  defp value(skill, key) when is_map(skill) do
    Map.get(skill, key) || Map.get(skill, Atom.to_string(key))
  end
end
