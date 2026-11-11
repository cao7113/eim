defmodule Eim.Accounts.ExtensionAuthCode do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "extension_auth_codes" do
    field :user_id, :binary_id
    field :code_hash, :binary
    field :code_challenge, :string
    field :expires_at, :utc_datetime_usec
    field :consumed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(code, attrs) do
    code
    |> cast(attrs, [:user_id, :code_hash, :code_challenge, :expires_at])
    |> validate_required([:user_id, :code_hash, :code_challenge, :expires_at])
  end
end
