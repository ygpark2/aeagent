defmodule AOS.AgentOS.ConfigTest do
  use ExUnit.Case, async: false

  alias AOS.AgentOS.Config

  test "cliproxy_api? is true only when config value is true" do
    original = Application.get_env(:aos, :cliproxy_api)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:aos, :cliproxy_api)
      else
        Application.put_env(:aos, :cliproxy_api, original)
      end
    end)

    Application.put_env(:aos, :cliproxy_api, true)
    assert Config.cliproxy_api?()

    Application.put_env(:aos, :cliproxy_api, false)
    refute Config.cliproxy_api?()

    Application.delete_env(:aos, :cliproxy_api)
    refute Config.cliproxy_api?()
  end
end
