defmodule AOS.UUIDTest do
  @moduledoc """
  Tests for the UUID helpers.
  """

  use ExUnit.Case

  alias AOS.UUID

  test "guid?/1 returns true with valid guid" do
    assert UUID.guid?(Ecto.UUID.generate())
  end

  test "guid?/1 returns false with invalid guid" do
    refute UUID.guid?("Not-a-guid")
    refute UUID.guid?("ec71f7e0-7264-5fc-ac02-d77322aeca3c")
    refute UUID.guid?("ec71g7e0-7264-5fcf-ac02-d77322aeca3c")
  end
end
