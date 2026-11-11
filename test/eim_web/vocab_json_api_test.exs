defmodule EimWeb.VocabJsonApiTest do
  use EimWeb.ConnCase, async: false
  require Ash.Query

  alias Eim.Accounts

  @email "vocab-user@example.com"

  setup do
    user = create_user(@email)
    token = create_api_key(user)

    %{user: user, token: token}
  end

  test "authenticated users can save, read, and idempotently repeat a vocabulary entry", %{
    token: token,
    conn: conn
  } do
    attrs = entry_attributes("gave", "give", "原始笔记")

    conn = post_vocab_entry(conn, token, attrs)

    assert %{
             "data" => %{
               "id" => id,
               "type" => "vocab-entry",
               "attributes" => %{
                 "term_key" => "give",
                 "lookup_text" => "gave",
                 "note" => "原始笔记"
               }
             }
           } = json_response(conn, 201)

    conn =
      build_conn()
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/vocab/entries?filter[term_key]=give")

    assert %{"data" => [%{"id" => ^id, "attributes" => %{"note" => "原始笔记"}}]} =
             json_response(conn, 200)

    conn =
      build_conn()
      |> post_vocab_entry(token, entry_attributes("give", "give", "不应覆盖"))

    assert %{"data" => %{"id" => ^id, "attributes" => %{"note" => "原始笔记"}}} =
             json_response(conn, 201)
  end

  test "does not expose another user's saved entries", %{token: token, conn: conn} do
    conn = post_vocab_entry(conn, token, entry_attributes("gave", "give", nil))
    assert response(conn, 201)

    other_user = create_user("other-vocab-user@example.com")
    other_token = create_api_key(other_user)

    conn =
      build_conn()
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("authorization", "Bearer #{other_token}")
      |> get("/api/vocab/entries?filter[term_key]=give")

    assert %{"data" => []} = json_response(conn, 200)
  end

  test "rejects unauthenticated collection access and writes", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> get("/api/vocab/entries")

    assert conn.status in [401, 403]

    conn =
      build_conn()
      |> post_vocab_entry(nil, entry_attributes("gave", "give", nil))

    assert conn.status in [401, 403]
  end

  test "rejects notes longer than the documented limit", %{token: token, conn: conn} do
    conn =
      post_vocab_entry(
        conn,
        token,
        entry_attributes("gave", "give", String.duplicate("x", 2001))
      )

    assert conn.status == 400
  end

  test "does not accept an owner supplied by the client", %{user: user, token: token, conn: conn} do
    other_user = create_user("forged-vocab-user@example.com")

    conn =
      post_vocab_entry(
        conn,
        token,
        Map.put(entry_attributes("gave", "give", nil), "user_id", other_user.id)
      )

    assert conn.status == 400

    query = Ash.Query.filter(Eim.Vocab.Entry, term_key == "give")
    assert {:ok, []} = Ash.read(query, domain: Eim.Vocab, actor: other_user)
    assert {:ok, []} = Ash.read(query, domain: Eim.Vocab, actor: user)
  end

  test "includes vocabulary routes in the Swagger OpenAPI document", %{token: token} do
    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/open_api")

    spec = conn |> response(200) |> Jason.decode!()

    assert is_map(spec["paths"]["/api/vocab/entries"])
  end

  defp post_vocab_entry(conn, token, attrs) do
    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("content-type", "application/vnd.api+json")

    conn =
      if token do
        put_req_header(conn, "authorization", "Bearer #{token}")
      else
        conn
      end

    post(conn, "/api/vocab/entries", %{
      "data" => %{
        "type" => "vocab-entry",
        "attributes" => attrs
      }
    })
  end

  defp entry_attributes(text, lemma, note) do
    %{
      "lookup_text" => text,
      "lemma" => lemma,
      "phonetic" => "ɡɪv",
      "dictionary_snapshot" => %{
        "text" => text,
        "kind" => "word",
        "match" => "exact",
        "lemma" => lemma,
        "phonetic" => "ɡɪv",
        "senses" => [%{"pos" => "verb", "domain" => nil, "zh" => "给"}]
      },
      "note" => note
    }
  end

  defp create_user(email) do
    {:ok, hashed_password} = AshAuthentication.BcryptProvider.hash("password123456")

    Ash.Seed.seed!(Accounts.User, %{
      email: email,
      hashed_password: hashed_password,
      confirmed_at: DateTime.utc_now()
    })
  end

  defp create_api_key(user) do
    {:ok, api_key} =
      Ash.create(
        Accounts.ApiKey,
        %{
          user_id: user.id,
          expires_at:
            DateTime.utc_now()
            |> DateTime.add(30 * 24 * 60 * 60, :second)
            |> DateTime.truncate(:microsecond)
        },
        domain: Accounts,
        authorize?: false
      )

    Ash.Resource.get_metadata(api_key, :plaintext_api_key)
  end
end
