defmodule AOS.AgentOS.Skills.Source.Filesystem do
  @moduledoc """
  Filesystem-backed skill source and export helpers.
  """

  alias AOS.AgentOS.Skills.Codec.TOML
  alias AOS.AgentOS.Skills.Skill
  alias AOS.Runtime.FileSystem

  @default_priority 0

  def skills_dir do
    Application.get_env(
      :aos,
      :agent_skills_dir,
      Path.join(:code.priv_dir(:aos), "agent_os/skills")
    )
  end

  def list_skills do
    skills_dir()
    |> list_skill_entries()
    |> Enum.flat_map(&load_skill_entry/1)
  end

  defp list_skill_entries(dir) do
    if FileSystem.dir?(dir) do
      case FileSystem.ls(dir) do
        {:ok, entries} -> Enum.map(entries, &{&1, Path.join(dir, &1)})
        {:error, _reason} -> []
      end
    else
      []
    end
  end

  defp load_skill_entry({skill_id, skill_path}) do
    if FileSystem.dir?(skill_path), do: [load_skill(skill_id, skill_path)], else: []
  end

  def load_skill(skill_name) do
    skill_path = Path.join(skills_dir(), skill_name)

    if FileSystem.dir?(skill_path) do
      {:ok, load_skill(skill_name, skill_path)}
    else
      {:error, :not_found}
    end
  end

  def export_skill(%Skill{} = skill, opts \\ []) do
    skill_path = Path.join(skills_dir(), skill.name)
    overwrite? = Keyword.get(opts, :overwrite, false)
    dry_run? = Keyword.get(opts, :dry_run, false)
    toml_path = Path.join(skill_path, "skill.toml")
    markdown_path = Path.join(skill_path, "SKILL.md")
    toml_content = TOML.encode_skill_metadata(skill)
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
        :ok = FileSystem.mkdir_p(skill_path)
        :ok = FileSystem.write(toml_path, toml_content)
        :ok = FileSystem.write(markdown_path, markdown_content)

        {:ok,
         %{
           action: :export,
           mode: if(overwrite?, do: :overwrite, else: :write),
           preview: preview.text
         }}
    end
  end

  def build_import_preview(skill_name, attrs) do
    %{skill_name: skill_name, attrs: attrs}
  end

  def compare_existing_file(path, new_content) do
    case FileSystem.read(path) do
      {:ok, existing} when existing == new_content -> :same
      {:ok, _existing} -> :different
      {:error, _} -> :missing
    end
  end

  def default_skill_markdown(%Skill{} = skill) do
    """
    # #{skill.name}

    #{skill.description}

    ## Instructions
    Add detailed instructions for this skill.
    """
    |> String.trim()
    |> Kernel.<>("\n")
  end

  def fs_skill_to_attrs(skill) do
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

  defp load_skill(skill_id, skill_path) do
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

    if FileSystem.exists?(skill_md) do
      {:ok, markdown} = FileSystem.read(skill_md)
      {extract_markdown_description(markdown), markdown}
    else
      description = "No description available for #{Path.basename(skill_path)}"
      {description, description}
    end
  end

  defp read_skill_metadata(skill_path) do
    skill_toml = Path.join(skill_path, "skill.toml")

    if FileSystem.exists?(skill_toml) do
      {:ok, content} = FileSystem.read(skill_toml)
      TOML.decode_skill_metadata(content)
    else
      %{}
    end
  end

  defp extract_markdown_description(markdown) do
    markdown
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or &1 == "---"))
    |> Enum.find_value(fn line ->
      cond do
        String.starts_with?(line, "# ") -> String.trim_leading(line, "# ")
        String.starts_with?(line, "name =") -> nil
        true -> nil
      end
    end) || "No description available"
  end

  defp build_export_preview(skill_path, toml_path, markdown_path, toml_content, markdown_content) do
    toml_status = compare_existing_file(toml_path, toml_content)
    markdown_status = compare_existing_file(markdown_path, markdown_content)
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

  defp status_label(:missing), do: "new file"
  defp status_label(:same), do: "unchanged"
  defp status_label(:different), do: "would overwrite"

  defp normalize_list(nil), do: []
  defp normalize_list(value) when is_list(value), do: Enum.map(value, &to_string/1)
  defp normalize_list(value) when is_binary(value), do: split_capabilities(value)
  defp normalize_list(value), do: [to_string(value)]

  defp split_capabilities(text) do
    text
    |> String.split([",", "\n"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_priority(value) when is_integer(value), do: value

  defp normalize_priority(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {priority, ""} -> priority
      _ -> @default_priority
    end
  end

  defp normalize_priority(_), do: @default_priority
end
