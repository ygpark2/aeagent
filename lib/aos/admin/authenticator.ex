defmodule AOS.Admin.Authenticator do
  @moduledoc """
  Handles admin authentication behind a configurable credential provider.
  """

  @default_provider AOS.Admin.Credentials.EnvProvider

  def authenticate(username, password) when is_binary(username) and is_binary(password) do
    provider().fetch_credentials()
    |> verify_credentials(username, password)
  end

  def authenticate(_, _), do: {:error, :invalid_credentials}

  def hash_password(password) when is_binary(password) do
    Argon2.hash_pwd_salt(password)
  end

  def valid_password?(password, password_hash)
      when is_binary(password) and is_binary(password_hash) and byte_size(password_hash) > 0 do
    Argon2.verify_pass(password, password_hash)
  end

  def valid_password?(_, _), do: false

  defp provider do
    Application.get_env(:aos, :admin_auth_provider, @default_provider)
  end

  defp verify_credentials(
         %{username: stored_username, password_hash: password_hash},
         username,
         password
       )
       when is_binary(password_hash) and byte_size(password_hash) > 0 do
    if username == stored_username and valid_password?(password, password_hash) do
      :ok
    else
      {:error, :invalid_credentials}
    end
  end

  defp verify_credentials(
         %{username: stored_username, password: stored_password},
         username,
         password
       ) do
    if username == stored_username and password == stored_password do
      :ok
    else
      {:error, :invalid_credentials}
    end
  end
end
