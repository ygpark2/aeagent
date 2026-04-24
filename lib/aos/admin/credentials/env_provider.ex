defmodule AOS.Admin.Credentials.EnvProvider do
  @moduledoc """
  Reads admin credentials from application environment.
  """

  def fetch_credentials do
    username = Application.get_env(:aos, :admin_username, "admin")
    password = Application.get_env(:aos, :admin_password, "admin")
    password_hash = Application.get_env(:aos, :admin_password_hash)

    %{
      username: username,
      password: password,
      password_hash: password_hash
    }
  end
end
