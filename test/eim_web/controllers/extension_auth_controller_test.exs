defmodule EimWeb.ExtensionAuthControllerTest do
  use EimWeb.ConnCase, async: false

  require Ash.Query

  alias Eim.Accounts.UserIdentity

  @extension_redirect_uri "https://mkbjhjbecifpejjljcjbadocpfiepoen.chromiumapp.org/"
  @email "extension-user@example.com"

  setup do
    original_client = Application.fetch_env(:eim, :extension_oidc_client)
    original_result = Application.fetch_env(:eim, :extension_oidc_stub_result)

    Application.put_env(:eim, :extension_oidc_client, Eim.StubExtensionOidc)

    on_exit(fn ->
      restore_env(:extension_oidc_client, original_client)
      restore_env(:extension_oidc_stub_result, original_result)
    end)

    :ok
  end

  test "exchanges an Authx code for a revocable API key" do
    stub_exchange(
      {:ok, %{"sub" => "authx-extension-sub", "email" => @email, "email_verified" => true},
       %{"access_token" => "authx-access-token"}}
    )

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/extension/authx", authx_payload())

    assert %{
             "token" => api_key,
             "key_id" => key_id,
             "user" => %{"email" => @email}
           } = json_response(conn, 200)

    assert {:ok, identity} =
             UserIdentity
             |> Ash.Query.filter(uid == "authx-extension-sub" and strategy == "authx")
             |> Ash.read_one(domain: Eim.Accounts, authorize?: false)

    assert to_string(identity.strategy) == "authx"

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{api_key}")
      |> get("/api/extension/me")

    assert %{"email" => @email} = json_response(conn, 200)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{api_key}")
      |> put_req_header("content-type", "application/json")
      |> delete("/api/extension/session", %{"key_id" => key_id})

    assert response(conn, 204) == ""

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{api_key}")
      |> get("/api/extension/me")

    assert response(conn, 401) == "Unauthorized"
  end

  test "rejects a redirect URI that is not registered for the extension client" do
    stub_exchange(
      {:ok, %{"sub" => "authx-extension-sub", "email" => @email, "email_verified" => true},
       %{"access_token" => "authx-access-token"}}
    )

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/extension/authx",
        Map.put(authx_payload(), "redirect_uri", "https://evil.example.com/")
      )

    assert response(conn, 400) == "Invalid extension authorization request"
  end

  test "rejects an Authx account whose email is not verified" do
    stub_exchange(
      {:ok, %{"sub" => "authx-extension-sub", "email" => @email, "email_verified" => false},
       %{"access_token" => "authx-access-token"}}
    )

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/extension/authx", authx_payload())

    assert response(conn, 401) == "Authx account email is not verified"
  end

  test "rejects an invalid or expired Authx code" do
    stub_exchange({:error, :invalid_code})

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/extension/authx", authx_payload())

    assert response(conn, 401) == "Invalid or expired authorization code"
  end

  defp verifier do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp stub_exchange(result) do
    Application.put_env(:eim, :extension_oidc_stub_result, result)
  end

  defp authx_payload do
    %{
      "code" => "authx-code",
      "state" => String.duplicate("s", 32),
      "nonce" => String.duplicate("n", 32),
      "code_verifier" => verifier(),
      "redirect_uri" => @extension_redirect_uri
    }
  end

  defp restore_env(key, {:ok, value}), do: Application.put_env(:eim, key, value)
  defp restore_env(key, :error), do: Application.delete_env(:eim, key)
end
