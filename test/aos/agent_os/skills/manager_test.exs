defmodule AOS.AgentOS.Skills.ManagerTest do
  use AOS.DataCase, async: true

  alias AOS.AgentOS.Skills.Manager
  alias AOS.AgentOS.Skills.Skill
  alias AOS.Repo

  setup do
    original = :application.get_env(:aos, :agent_skills_dir, nil)

    on_exit(fn ->
      if original do
        Application.put_env(:aos, :agent_skills_dir, original)
      else
        Application.delete_env(:aos, :agent_skills_dir)
      end
    end)
  end

  test "normalizes JSON capability strings from database skills" do
    name = "research_pro_#{System.unique_integer([:positive])}"

    Repo.insert!(%Skill{
      name: name,
      description: "Research helper",
      instructions: "Use search carefully",
      capabilities: "[\"search\",\"synthesis\"]",
      is_active: true
    })

    skill =
      Manager.list_active_skills()
      |> Enum.find(&(&1.name == name))

    assert skill.capabilities == ["search", "synthesis"]
  end

  test "loads filesystem skill metadata from skill.toml" do
    skill =
      Manager.list_active_skills()
      |> Enum.find(&(&1.name == "example_skill"))

    assert skill.description ==
             "Shell access guidance for filesystem inspection and command-driven tasks."

    assert skill.capabilities == ["ls", "read_file", "grep_search", "execute_command"]
    assert skill.tags == ["shell", "filesystem", "cli"]

    assert skill.triggers == [
             "list files",
             "read files",
             "search codebase",
             "run shell command"
           ]

    assert skill.priority == 25
    assert skill.execution_mode == "assisted"
    assert skill.permissions == ["file_read"]
    assert skill.required_tools == ["ls", "read_file", "grep_search", "execute_command"]
  end

  test "normalizes execution metadata from database skills" do
    name = "assisted_skill_#{System.unique_integer([:positive])}"

    Repo.insert!(%Skill{
      name: name,
      description: "Assisted database-backed skill",
      instructions: "Use tools selectively",
      capabilities: "read_file,write_file",
      tags: "filesystem,editing",
      triggers: "edit file,inspect project",
      priority: 40,
      execution_mode: "assisted",
      permissions: "file_read,file_write",
      required_tools: "read_file,write_file",
      is_active: true
    })

    skill =
      Manager.list_active_skills()
      |> Enum.find(&(&1.name == name))

    assert skill.tags == ["filesystem", "editing"]
    assert skill.triggers == ["edit file", "inspect project"]
    assert skill.priority == 40
    assert skill.execution_mode == "assisted"
    assert skill.permissions == ["file_read", "file_write"]
    assert skill.required_tools == ["read_file", "write_file"]
  end

  test "exports database skills to filesystem skill files" do
    tmp_dir = Path.join(System.tmp_dir!(), "skill-export-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    Application.put_env(:aos, :agent_skills_dir, tmp_dir)
    skill_name = "exportable_skill_#{System.unique_integer([:positive])}"

    skill =
      Repo.insert!(%Skill{
        name: skill_name,
        description: "Export this skill",
        instructions: "# Exportable Skill\n\nUse careful steps.",
        capabilities: "read_file,write_file",
        tags: "filesystem,export",
        triggers: "export skill,write file",
        priority: 30,
        execution_mode: "assisted",
        permissions: "file_read,file_write",
        required_tools: "read_file,write_file",
        is_active: true
      })

    assert {:ok, %{mode: :write}} = Manager.export_skill_to_filesystem(skill, overwrite: false)
    assert File.exists?(Path.join([tmp_dir, skill_name, "skill.toml"]))
    assert File.exists?(Path.join([tmp_dir, skill_name, "SKILL.md"]))

    toml = File.read!(Path.join([tmp_dir, skill_name, "skill.toml"]))
    assert toml =~ ~s(name = "#{skill_name}")
    assert toml =~ ~s(mode = "assisted")
    assert toml =~ ~s(required_tools = ["read_file", "write_file"])
  end

  test "preview export reports overwrite conflicts without writing files" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "skill-preview-export-#{System.unique_integer([:positive])}")

    skill_name = "preview_skill_#{System.unique_integer([:positive])}"
    skill_dir = Path.join(tmp_dir, skill_name)
    File.mkdir_p!(skill_dir)
    Application.put_env(:aos, :agent_skills_dir, tmp_dir)

    File.write!(Path.join(skill_dir, "skill.toml"), "old")
    File.write!(Path.join(skill_dir, "SKILL.md"), "old")

    skill =
      Repo.insert!(%Skill{
        name: skill_name,
        description: "Preview me",
        instructions: "# Preview Skill",
        is_active: true
      })

    assert {:ok, %{mode: :preview, preview: preview, conflict?: true}} =
             Manager.preview_export_skill_to_filesystem(skill)

    assert preview =~ "would overwrite"

    assert {:error, %{reason: :already_exists, preview: blocked_preview}} =
             Manager.export_skill_to_filesystem(skill, overwrite: false)

    assert blocked_preview =~ "would overwrite"
  end

  test "imports filesystem skill into database" do
    tmp_dir = Path.join(System.tmp_dir!(), "skill-import-#{System.unique_integer([:positive])}")
    skill_name = "imported_skill_#{System.unique_integer([:positive])}"
    skill_dir = Path.join(tmp_dir, skill_name)
    File.mkdir_p!(skill_dir)
    Application.put_env(:aos, :agent_skills_dir, tmp_dir)

    File.write!(
      Path.join(skill_dir, "skill.toml"),
      """
      [skill]
      name = "#{skill_name}"
      description = "Imported from filesystem"
      tags = ["fs", "import"]
      triggers = ["import skill"]
      capabilities = ["read_file"]

      [execution]
      mode = "assisted"
      required_tools = ["read_file"]
      permissions = ["file_read"]

      [selection]
      priority = 15
      """
    )

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      """
      # Imported Skill

      Use this imported skill carefully.
      """
    )

    assert {:ok, %Skill{} = skill} =
             Manager.import_skill_from_filesystem(skill_name, overwrite: false)

    assert skill.name == skill_name
    assert skill.execution_mode == "assisted"
    assert skill.permissions == "file_read"
    assert skill.required_tools == "read_file"
  end

  test "preview import reports existing database conflicts" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "skill-preview-import-#{System.unique_integer([:positive])}")

    skill_name = "conflict_skill_#{System.unique_integer([:positive])}"
    skill_dir = Path.join(tmp_dir, skill_name)
    File.mkdir_p!(skill_dir)
    Application.put_env(:aos, :agent_skills_dir, tmp_dir)

    Repo.insert!(%Skill{
      name: skill_name,
      description: "DB version",
      instructions: "db",
      execution_mode: "prompt_only",
      permissions: "",
      required_tools: "",
      is_active: true
    })

    File.write!(
      Path.join(skill_dir, "skill.toml"),
      """
      [skill]
      name = "#{skill_name}"
      description = "Filesystem version"

      [execution]
      mode = "assisted"
      required_tools = ["read_file"]
      permissions = ["file_read"]

      [selection]
      priority = 9
      """
    )

    File.write!(Path.join(skill_dir, "SKILL.md"), "# Conflict Skill")

    assert {:ok, %{mode: :preview, preview: preview, conflict?: true}} =
             Manager.preview_import_skill_from_filesystem(skill_name)

    assert preview =~ "database skill: existing"

    assert {:error, %{reason: :already_exists}} =
             Manager.import_skill_from_filesystem(skill_name, overwrite: false)
  end
end
