defmodule AOS.TestModel do
  @moduledoc """
  Test Model
  """
  use AOS.Schema

  schema "test_models" do
    field :field, :string
  end
end
