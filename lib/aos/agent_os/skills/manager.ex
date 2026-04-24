defmodule AOS.AgentOS.Skills.Manager do
  @moduledoc """
  Manager for loading and listing skills.
  Primary source is the `agent_skills` database table.
  """
  require Logger
  import Ecto.Query
  alias AOS.Repo
  alias AOS.AgentOS.Skills.Skill

  @default_priority 0

  def skills_dir do
    Application.get_env(
      :aos,
      :agent_skills_dir,
      Path.join(:code.priv_dir(:aos), "agent_os/skills")
    )
  end

  def list_active_skills do
    db_skills =
      Skill
      |> where([s], s.is_active == true)
      |> Repo.all()
      |> Enum.map(&normalize_skill/1)

    fs_skills = list_fs_skills()

    (fs_skills ++ db_skills)
    |> Enum.uniq_by(& &1.name)
  end

  def list_all_skills do
    # For Admin: list all skills from the DB
    Repo.all(Skill)
  end

  def get_skill!(id), do: Repo.get!(Skill, id)

  def export_skill_to_filesystem(skill_or_id, opts \\ [])

  def export_skill_to_filesystem(%Skill{} = skill, opts) do
    skill = Repo.preload(skill, [])
    skill_path = Path.join(skills_dir(), skill.name)
    overwrite? = Keyword.get(opts, :overwrite, false)
    dry_run? = Keyword.get(opts, :dry_run, false)
    toml_path = Path.join(skill_path, "skill.toml")
    markdown_path = Path.join(skill_path, "SKILL.md")
    toml_content = render_skill_toml(skill)
    markdown_content = skill.instructions || default_skill_markdown(skill)

    preview =
      build_export_preview(skill_path, toml_path, markdown_path, toml_content, markdown_content)

    cond do
      dry_run? ->
        {:ok,
         %{action: :export, mode: :preview, conflict?: preview.conflict?, preview: preview.text}}

      preview.conflict? and not overwrite? ->
        {:error, %{reason: :already_exists, preview: preview.text}}

      true ->
        File.mkdir_p!(skill_path)
        File.write!(toml_path, toml_content)
        File.write!(markdown_path, markdown_content)

        {:ok,
         %{
           action: :export,
           mode: if(overwrite?, do: :overwrite, else: :write),
           preview: preview.text
         }}
    end
  end

  def export_skill_to_filesystem(id, opts) when is_integer(id) do
    id
    |> get_skill!()
    |> export_skill_to_filesystem(opts)
  end

  def preview_export_skill_to_filesystem(%Skill{} = skill) do
    export_skill_to_filesystem(skill, dry_run: true)
  end

  def preview_export_skill_to_filesystem(id) when is_integer(id) do
    id
    |> get_skill!()
    |> preview_export_skill_to_filesystem()
  end

  def preview_import_skill_from_filesystem(skill_name) do
    import_skill_from_filesystem(skill_name, dry_run: true)
  end

  def import_skill_from_filesystem(skill_name, opts \\ []) do
    skill_path = Path.join(skills_dir(), skill_name)
    overwrite? = Keyword.get(opts, :overwrite, false)
    dry_run? = Keyword.get(opts, :dry_run, false)

    if File.dir?(skill_path) do
      fs_skill = load_fs_skill(skill_name, skill_path)
      attrs = fs_skill_to_attrs(fs_skill)
      preview = build_import_preview(fs_skill.name, attrs)

      cond do
        dry_run? ->
          {:ok,
           %{action: :import, mode: :preview, conflict?: preview.conflict?, preview: preview.text}}

        preview.conflict? and not overwrite? ->
          {:error, %{reason: :already_exists, preview: preview.text}}

        true ->
          case Repo.get_by(Skill, name: fs_skill.name) do
            nil ->
              register_skill(attrs)

            %Skill{} = skill ->
              skill
              |> Skill.changeset(attrs)
              |> Repo.update()
          end
      end
    else
      {:error, :not_found}
    end
  end

  defp list_fs_skills do
    skills_dir = skills_dir()

    if File.dir?(skills_dir) do
      File.ls!(skills_dir)
      |> Enum.map(fn skill_id ->
        skill_path = Path.join(skills_dir, skill_id)

        if File.dir?(skill_path) do
          load_fs_skill(skill_id, skill_path)
        end
      end)
      |> Enum.filter(& &1)
    else
      []
    end
  end

  defp load_fs_skill(skill_id, skill_path) do
    metadata = read_skill_metadata(skill_path)
    {description, instructions} = read_skill_markdown(skill_path)

    %{
      name: metadata[:name] || skill_id,
      description: metadata[:description] || description,
      instructions: instructions,
      capabilities: normalize_list(metadata[:capabilities]),
      tags: normalize_list(metadata[:tags]),
      triggers: normalize_list(metadata[:triggers]),
      priority: normalize_priority(metadata[:priority]),
      execution_mode: metadata[:execution_mode] || "prompt_only",
      permissions: normalize_list(metadata[:permissions]),
      required_tools: normalize_list(metadata[:required_tools]),
      source: :filesystem
    }
  end

  defp read_skill_markdown(skill_path) do
    skill_md = Path.join(skill_path, "SKILL.md")

    if File.exists?(skill_md) do
      markdown = File.read!(skill_md)
      {extract_markdown_description(markdown), markdown}
    else
      description = "No description available for #{Path.basename(skill_path)}"
      {description, description}
    end
  end

  defp extract_markdown_description(markdown) do
    markdown
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or &1 == "---"))
    |> Enum.find_value(fn line ->
      cond do
        String.starts_with?(line, "# ") ->
          String.trim_leading(line, "# ")

        String.starts_with?(line, "name =") ->
          nil

        true ->
          nil
      end
    end) || "No description available"
  end

  defp read_skill_metadata(skill_path) do
    skill_toml = Path.join(skill_path, "skill.toml")

    if File.exists?(skill_toml) do
      skill_toml
      |> File.read!()
      |> parse_simple_toml()
      |> flatten_skill_metadata()
    else
      %{}
    end
  end

  def register_skill(attrs) do
    %Skill{}
    |> Skill.changeset(attrs)
    |> Repo.insert()
  end

  def get_skills_by_names(names) do
    names = MapSet.new(names)

    list_active_skills()
    |> Enum.filter(&MapSet.member?(names, &1.name))
  end

  defp normalize_skill(%Skill{} = skill) do
    %{
      name: skill.name,
      description: skill.description,
      instructions: skill.instructions,
      capabilities: normalize_capabilities(skill.capabilities),
      tags: normalize_list(skill.tags),
      triggers: normalize_list(skill.triggers),
      priority: normalize_priority(skill.priority),
      execution_mode: skill.execution_mode || "prompt_only",
      permissions: normalize_list(skill.permissions),
      required_tools: normalize_list(skill.required_tools),
      source: :database
    }
  end

  defp normalize_capabilities(nil), do: []
  defp normalize_capabilities(capabilities) when is_list(capabilities), do: capabilities

  defp normalize_capabilities(capabilities) when is_binary(capabilities) do
    trimmed = String.trim(capabilities)

    cond do
      trimmed == "" ->
        []

      String.starts_with?(trimmed, "[") ->
        case Jason.decode(trimmed) do
          {:ok, list} when is_list(list) -> Enum.map(list, &to_string/1)
          _ -> split_capabilities(trimmed)
        end

      true ->
        split_capabilities(trimmed)
    end
  end

  defp normalize_capabilities(other), do: [to_string(other)]

  defp split_capabilities(text) do
    text
    |> String.split([",", "\n"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_list(nil), do: []
  defp normalize_list(value) when is_list(value), do: Enum.map(value, &to_string/1)
  defp normalize_list(value) when is_binary(value), do: split_capabilities(value)
  defp normalize_list(value), do: [to_string(value)]

  defp normalize_priority(value) when is_integer(value), do: value

  defp normalize_priority(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {priority, ""} -> priority
      _ -> @default_priority
    end
  end

  defp normalize_priority(_), do: @default_priority

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

  defp build_export_preview(skill_path, toml_path, markdown_path, toml_content, markdown_content) do
    toml_status = compare_file_status(toml_path, toml_content)
    markdown_status = compare_file_status(markdown_path, markdown_content)
    conflict? = toml_status != :missing or markdown_status != :missing

    %{
      conflict?: conflict?,
      text:
        """
        Export target: #{skill_path}
        skill.toml: #{status_label(toml_status)}
        SKILL.md: #{status_label(markdown_status)}
        """
        |> String.trim()
    }
  end

  defp build_import_preview(skill_name, attrs) do
    existing = Repo.get_by(Skill, name: skill_name)

    lines =
      case existing do
        nil ->
          [
            "Import source: #{Path.join(skills_dir(), skill_name)}",
            "database skill: missing",
            "result: create new database skill"
          ]

        %Skill{} = skill ->
          [
            "Import source: #{Path.join(skills_dir(), skill_name)}",
            "database skill: existing",
            "description: #{diff_label(skill.description, attrs.description)}",
            "execution_mode: #{diff_label(skill.execution_mode, attrs.execution_mode)}",
            "permissions: #{diff_label(skill.permissions, attrs.permissions)}",
            "required_tools: #{diff_label(skill.required_tools, attrs.required_tools)}"
          ]
      end

    %{conflict?: not is_nil(existing), text: Enum.join(lines, "\n")}
  end

  defp compare_file_status(path, new_content) do
    case File.read(path) do
      {:ok, existing} when existing == new_content -> :same
      {:ok, _existing} -> :different
      {:error, _} -> :missing
    end
  end

  defp status_label(:missing), do: "new file"
  defp status_label(:same), do: "unchanged"
  defp status_label(:different), do: "would overwrite"

  defp diff_label(current, incoming) when current == incoming, do: "unchanged"
  defp diff_label(current, incoming), do: "#{current || "nil"} -> #{incoming || "nil"}"

  defp fs_skill_to_attrs(skill) do
    %{
      name: skill.name,
      description: skill.description,
      instructions: skill.instructions,
      capabilities: Enum.join(skill.capabilities || [], ","),
      tags: Enum.join(skill.tags || [], ","),
      triggers: Enum.join(skill.triggers || [], ","),
      priority: skill.priority || @default_priority,
      execution_mode: skill.execution_mode || "prompt_only",
      permissions: Enum.join(skill.permissions || [], ","),
      required_tools: Enum.join(skill.required_tools || [], ","),
      is_active: true
    }
  end

  defp render_skill_toml(%Skill{} = skill) do
    """
    [skill]
    name = "#{skill.name}"
    description = "#{escape_toml(skill.description)}"
    tags = #{render_toml_array(skill.tags)}
    triggers = #{render_toml_array(skill.triggers)}
    capabilities = #{render_toml_array(skill.capabilities)}
    is_active = #{if(skill.is_active, do: "true", else: "false")}

    [execution]
    mode = "#{skill.execution_mode || "prompt_only"}"
    required_tools = #{render_toml_array(skill.required_tools)}
    permissions = #{render_toml_array(skill.permissions)}

    [selection]
    priority = #{skill.priority || @default_priority}
    """
    |> String.trim()
    |> Kernel.<>("\n")
  end

  defp default_skill_markdown(%Skill{} = skill) do
    """
    # #{skill.name}

    #{skill.description}

    ## Instructions
    Add detailed instructions for this skill.
    """
    |> String.trim()
    |> Kernel.<>("\n")
  end

  defp render_toml_array(nil), do: "[]"

  defp render_toml_array(value) do
    value
    |> normalize_list()
    |> Enum.map_join(", ", fn item -> "\"#{escape_toml(item)}\"" end)
    |> then(&"[#{&1}]")
  end

  defp escape_toml(nil), do: ""

  defp escape_toml(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end
end
