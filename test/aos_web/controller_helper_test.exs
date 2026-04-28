defmodule AOSWeb.ControllerHelperTest do
  @moduledoc """
  Tests for the ControllerHelper.
  """

  use AOSWeb.ConnCase
  use AOS.Constants.General
  use AOS.TestConstants

  require AOS.Enums

  alias AOSWeb.ControllerHelper

  describe "recursive_keys_to_camel_string/3" do
    @map %{
      parent_key: %{another_key: %{inside_key: "value"}, some_key: "value"},
      out_side_key: "value"
    }

    test "returns the passed map with all keys under the passed key converted to camelCase strings" do
      expected_map = %{
        parent_key: %{
          "anotherKey" => %{"insideKey" => "value"},
          "someKey" => "value"
        },
        out_side_key: "value"
      }

      assert expected_map == @map |> ControllerHelper.recursive_keys_to_camel_string(:parent_key)
    end

    test "returns the passed map with all keys under the passed key converted to camelCase strings except the excluded children are only stringified" do
      expected_map = %{
        parent_key: %{
          "another_key" => %{"inside_key" => "value"},
          "someKey" => "value"
        },
        out_side_key: "value"
      }

      assert expected_map ==
               @map
               |> ControllerHelper.recursive_keys_to_camel_string(:parent_key, [:another_key])
    end

    test "returns the passed map with all keys under the passed key converted to camelCase strings except the excluded children are only stringified and its non-map values are left alone" do
      expected_map = %{
        parent_key: %{
          "anotherKey" => %{"insideKey" => "value"},
          "some_key" => "value"
        },
        out_side_key: "value"
      }

      assert expected_map ==
               @map
               |> ControllerHelper.recursive_keys_to_camel_string(:parent_key, [:some_key])
    end

    test "returns the passed map with no changes" do
      assert @map == @map |> ControllerHelper.recursive_keys_to_camel_string(:no_key)
    end
  end

  describe "remove_nils_from_map/1" do
    map = %{"key" => nil}

    assert %{} == map |> ControllerHelper.remove_nils_from_map()
  end
end
