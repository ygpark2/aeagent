defmodule AOS.AgentOS.Skills.Codec.TOMLTest do
  use ExUnit.Case, async: true

  alias AOS.AgentOS.Skills.Codec.TOML

  test "decodes skill metadata from toml" do
    metadata =
      TOML.decode_skill_metadata("""
      [skill]
      name = "example_skill"
      description = "Example description"
      tags = ["shell", "filesystem"]
      triggers = ["list files"]
      capabilities = ["read_file"]
      is_active = true

      [execution]
      mode = "assisted"
      required_tools = ["read_file"]
      permissions = ["file_read"]

      [selection]
      priority = 25
      """)

    assert metadata.name == "example_skill"
    assert metadata.description == "Example description"
    assert metadata.tags == ["shell", "filesystem"]
    assert metadata.triggers == ["list files"]
    assert metadata.capabilities == ["read_file"]
    assert metadata.is_active == true
    assert metadata.execution_mode == "assisted"
    assert metadata.required_tools == ["read_file"]
    assert metadata.permissions == ["file_read"]
    assert metadata.priority == 25
  end

  test "encodes skill metadata to toml" do
    toml =
      TOML.encode_skill_metadata(%{
        name: "example_skill",
        description: "Example description",
        tags: ["shell", "filesystem"],
        triggers: ["list files"],
        capabilities: ["read_file"],
        is_active: true,
        execution_mode: "assisted",
        required_tools: ["read_file"],
        permissions: ["file_read"],
        priority: 25
      })

    assert toml =~ ~s(name = "example_skill")
    assert toml =~ ~s(description = "Example description")
    assert toml =~ ~s(mode = "assisted")
    assert toml =~ ~s(required_tools = ["read_file"])
    assert toml =~ ~s(permissions = ["file_read"])
    assert toml =~ ~s(priority = 25)
  end
end
