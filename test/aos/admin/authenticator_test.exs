defmodule AOS.Admin.AuthenticatorTest do
  use ExUnit.Case, async: true

  alias AOS.Admin.Authenticator

  setup do
    original_provider = Application.get_env(:aos, :admin_auth_provider)
    original_username = Application.get_env(:aos, :admin_username)
    original_password = Application.get_env(:aos, :admin_password)
    original_hash = Application.get_env(:aos, :admin_password_hash)

    on_exit(fn ->
      restore_env(:admin_auth_provider, original_provider)
      restore_env(:admin_username, original_username)
      restore_env(:admin_password, original_password)
      restore_env(:admin_password_hash, original_hash)
    end)
  end

  test "authenticates with plain password from provider config" do
    Application.put_env(:aos, :admin_auth_provider, AOS.Admin.Credentials.EnvProvider)
    Application.put_env(:aos, :admin_username, "admin")
    Application.put_env(:aos, :admin_password, "secret")
    Application.delete_env(:aos, :admin_password_hash)

    assert :ok == Authenticator.authenticate("admin", "secret")
    assert {:error, :invalid_credentials} == Authenticator.authenticate("admin", "wrong")
  end

  test "authenticates with password hash when configured" do
    hash = Authenticator.hash_password("secret")

    Application.put_env(:aos, :admin_auth_provider, AOS.Admin.Credentials.EnvProvider)
    Application.put_env(:aos, :admin_username, "admin")
    Application.put_env(:aos, :admin_password, "ignored")
    Application.put_env(:aos, :admin_password_hash, hash)

    assert :ok == Authenticator.authenticate("admin", "secret")
    assert {:error, :invalid_credentials} == Authenticator.authenticate("admin", "wrong")
  end

  defp restore_env(key, nil), do: Application.delete_env(:aos, key)
  defp restore_env(key, value), do: Application.put_env(:aos, key, value)
end
