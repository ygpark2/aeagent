defmodule AOS.EctoEnumsTest do
  @moduledoc """
  Tests for the EctoEnums.
  """

  use AOS.DataCase
  use AOS.Constants.Enums

  alias AOS.EnvironmentEnum

  test "EnvironmentEnum has the values in the constant" do
    assert EnvironmentEnum.__enum_map__() == @environment_const
  end
end
