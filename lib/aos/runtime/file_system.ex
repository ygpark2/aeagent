defmodule AOS.Runtime.FileSystem do
  @moduledoc """
  Thin filesystem adapter for runtime services and MCP tools.
  """

  def read(path), do: File.read(path)
  def write(path, content), do: File.write(path, content)
  def mkdir_p(path), do: File.mkdir_p(path)
  def dir?(path), do: File.dir?(path)
  def exists?(path), do: File.exists?(path)
  def ls(path), do: File.ls(path)
end
