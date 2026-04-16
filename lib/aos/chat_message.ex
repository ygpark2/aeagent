defmodule AOS.ChatMessage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "chat_messages" do
    field :role, :string
    field :content, :string

    timestamps()
  end

  def changeset(chat_message, attrs) do
    chat_message
    |> cast(attrs, [:role, :content])
    |> validate_required([:role, :content])
  end
end
