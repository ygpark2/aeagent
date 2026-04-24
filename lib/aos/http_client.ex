defmodule AOS.HTTPClient do
  @moduledoc """
  Thin HTTP adapter so runtime services do not depend on HTTPoison directly.
  """

  def get(url, headers \\ [], opts \\ []) do
    case HTTPoison.get(url, headers, opts) do
      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        {:ok, %{status: status, body: body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  def post(url, body, headers \\ [], opts \\ []) do
    case HTTPoison.post(url, body, headers, opts) do
      {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
        {:ok, %{status: status, body: response_body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end
end
