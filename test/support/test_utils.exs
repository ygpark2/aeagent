defmodule AOS.TestUtils do
  @moduledoc """
  Test Utility functions.
  """

  alias AOS.SchemaHelper

  def map_fully_replicated?(original_map, new_map) do
    original_map
    |> Enum.reduce(true, fn {key, item}, accum ->
      new_map
      |> Map.get(key)
      |> equal?(item)
      |> case do
        true -> accum
        false -> false
      end
    end)
  end

  def props_are_equal?(props, map1, map2, ignore \\ [])
  def props_are_equal?(_, nil, nil, _), do: true
  def props_are_equal?(_, nil, _, _), do: false
  def props_are_equal?(_, _, nil, _), do: false

  def props_are_equal?(props, map1, map2, ignore) do
    ignore = ignore |> Enum.map(fn value -> value |> to_string() |> Recase.to_camel() end)

    map1 =
      map1 |> SchemaHelper.ensure_map() |> Recase.Enumerable.stringify_keys(&Recase.to_camel/1)

    map2 =
      map2 |> SchemaHelper.ensure_map() |> Recase.Enumerable.stringify_keys(&Recase.to_camel/1)

    props
    |> Enum.all?(fn prop ->
      prop = prop |> to_string() |> Recase.to_camel()

      if prop in ignore do
        true
      else
        Map.get(map1, prop) |> equal?(Map.get(map2, prop))
      end
    end)
  end

  defp equal?(%DateTime{} = one, %DateTime{} = two) do
    Timex.diff(one, two, :second) <= 1
  end

  defp equal?(one, two) when is_atom(one), do: equal?(one |> to_string, two)
  defp equal?(one, two) when is_atom(two), do: equal?(one, two |> to_string)
  defp equal?(one, two), do: one === two
end
