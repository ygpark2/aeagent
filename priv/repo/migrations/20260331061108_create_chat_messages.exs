defmodule AOS.Repo.Migrations.CreateChatMessages do
  use Ecto.Migration

  def change do
    create table(:chat_messages) do
      add :role, :string
      add :content, :text

      timestamps()
    end
  end
end
