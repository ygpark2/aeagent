defmodule AOS.DataFactory do
  @moduledoc """
  All data factories are imported here so they are available from a single location and factories may be used within other factories.
  """

  require AOS.Enums

  use ExMachina.Ecto, repo: AOS.Repo

  def generate_percent, do: :rand.uniform(100)

  def generate_random_string(length \\ 16) do
    :crypto.strong_rand_bytes(length) |> Base.url_encode64() |> binary_part(0, length)
  end
end
