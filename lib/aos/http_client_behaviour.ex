defmodule AOS.HTTPClient.Behaviour do
  @moduledoc """
  Defines the interface for HTTP operations to enable type-safe mocking with Mox.
  """
  @callback get(String.t(), list(), list()) :: {:ok, map()} | {:error, any()}
  @callback post(String.t(), any(), list(), list()) :: {:ok, map()} | {:error, any()}
end
