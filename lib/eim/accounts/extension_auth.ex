defmodule Eim.Accounts.ExtensionAuth do
  import Ecto.Query

  alias Eim.Accounts.ExtensionAuthCode
  alias Eim.Repo

  @code_lifetime_seconds 300

  def issue_code(user_id, code_challenge) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    code = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    code_hash = :crypto.hash(:sha256, code)

    Repo.delete_all(
      from code in ExtensionAuthCode,
        where: code.expires_at < ^now or not is_nil(code.consumed_at)
    )

    attrs = %{
      user_id: user_id,
      code_hash: code_hash,
      code_challenge: code_challenge,
      expires_at: DateTime.add(now, @code_lifetime_seconds, :second)
    }

    case %ExtensionAuthCode{} |> ExtensionAuthCode.changeset(attrs) |> Repo.insert() do
      {:ok, _record} -> {:ok, code}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def consume_code(code, verifier)
      when is_binary(code) and byte_size(code) in 40..50 and is_binary(verifier) and
             byte_size(verifier) in 43..128 do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    code_hash = :crypto.hash(:sha256, code)
    challenge = code_challenge(verifier)

    query =
      from auth_code in ExtensionAuthCode,
        where:
          auth_code.code_hash == ^code_hash and auth_code.code_challenge == ^challenge and
            auth_code.expires_at > ^now and is_nil(auth_code.consumed_at),
        lock: "FOR UPDATE"

    case Repo.one(query) do
      %ExtensionAuthCode{user_id: user_id} = record ->
        case record |> Ecto.Changeset.change(consumed_at: now) |> Repo.update() do
          {:ok, _record} -> {:ok, user_id}
          {:error, _changeset} -> {:error, :invalid_code}
        end

      nil ->
        {:error, :invalid_code}
    end
  end

  def consume_code(_code, _verifier), do: {:error, :invalid_code}

  def code_challenge(verifier) do
    :crypto.hash(:sha256, verifier)
    |> Base.url_encode64(padding: false)
  end
end
