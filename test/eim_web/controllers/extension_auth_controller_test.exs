defmodule EimWeb.ExtensionAuthControllerTest do
  use EimWeb.ConnCase, async: false

  alias Eim.Accounts
  alias Eim.Accounts.ExtensionAuth

  @redirect_uri "https://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.chromiumapp.org/"
  @email "extension-user@example.com"

  test "authorization redirects unauthenticated users to web sign-in and returns after login", %{
    conn: conn
  } do
    verifier = verifier()
    challenge = ExtensionAuth.code_challenge(verifier)
    state = verifier()
    url = authorization_url(challenge, state)

    conn = get(conn, url)
    assert redirected_to(conn) == "/sign-in"

    user = sign_in_user(create_user())

    conn =
      conn
      |> recycle()
      |> init_test_session(%{})
      |> AshAuthentication.Plug.Helpers.store_in_session(user)
      |> get(url)

    callback = URI.parse(redirected_to(conn))
    assert callback.scheme == "https"
    assert callback.host == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.chromiumapp.org"
    assert %{"state" => ^state, "code" => code} = URI.decode_query(callback.fragment)
    assert byte_size(code) == 43
  end

  test "authorization code is PKCE-bound, single-use, and exchanged for a revocable API key", %{
    conn: conn
  } do
    user = create_user()
    verifier = verifier()
    challenge = ExtensionAuth.code_challenge(verifier)
    {:ok, code} = ExtensionAuth.issue_code(user.id, challenge)

    conn =
      post(conn, "/api/extension/token", %{
        "code" => code,
        "code_verifier" => verifier <> "wrong"
      })

    assert response(conn, 401) == "Invalid or expired authorization code"

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/extension/token", %{
        "code" => code,
        "code_verifier" => verifier
      })

    assert %{
             "token" => api_key,
             "key_id" => key_id,
             "user" => %{"email" => @email}
           } = json_response(conn, 200)

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

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/extension/token", %{
        "code" => code,
        "code_verifier" => verifier
      })

    assert response(conn, 401) == "Invalid or expired authorization code"
  end

  test "rejects callback URIs outside Chrome identity callbacks", %{conn: conn} do
    verifier = verifier()
    challenge = ExtensionAuth.code_challenge(verifier)

    url =
      "/extension/authorize?" <>
        URI.encode_query(%{
          "redirect_uri" => "https://example.com/",
          "code_challenge" => challenge,
          "state" => verifier
        })

    conn = get(conn, url)
    assert response(conn, 400) == "Invalid extension authorization request"
  end

  defp authorization_url(challenge, state) do
    "/extension/authorize?" <>
      URI.encode_query(%{
        "redirect_uri" => @redirect_uri,
        "code_challenge" => challenge,
        "state" => state
      })
  end

  defp verifier do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp create_user do
    {:ok, hashed_password} = AshAuthentication.BcryptProvider.hash("password123456")

    Ash.Seed.seed!(Accounts.User, %{
      email: @email,
      hashed_password: hashed_password,
      confirmed_at: DateTime.utc_now()
    })
  end

  defp sign_in_user(user) do
    strategy = AshAuthentication.Info.strategy!(Accounts.User, :password)

    {:ok, authenticated_user} =
      AshAuthentication.Strategy.action(strategy, :sign_in, %{
        email: user.email,
        password: "password123456"
      })

    authenticated_user
  end
end
