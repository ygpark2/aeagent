defmodule AOS.Enums do
  @moduledoc """
  The Enum provides a location for all enum related macros.
  """

  use AOS.Constants.Enums

  defmacro environment_const, do: Macro.expand(@environment_const, __CALLER__)
end
