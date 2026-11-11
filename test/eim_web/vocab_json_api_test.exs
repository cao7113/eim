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

  test "rejects unauthenticated note updates and deletions", %{user: user} do
    {:ok, entry} =
      Ash.create(
        Eim.Vocab.Entry,
        entry_attributes("saved", "saved", nil),
        action: :create,
        domain: Eim.Vocab,
        actor: user
      )

    conn =
      build_conn()
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("content-type", "application/vnd.api+json")
      |> patch("/api/vocab/entries/#{entry.id}", %{
        "data" => %{
          "type" => "vocab-entry",
          "id" => entry.id,
          "attributes" => %{"note" => "not signed in"}
        }
      })

    assert conn.status in [401, 403]

    conn =
      build_conn()
      |> put_req_header("accept", "application/vnd.api+json")
      |> delete("/api/vocab/entries/#{entry.id}")

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

  test "owners can update and clear their note but cannot update other entry attributes", %{
    token: token,
    user: user,
    conn: conn
  } do
    conn = post_vocab_entry(conn, token, entry_attributes("gave", "give", "first note"))
    assert %{"data" => %{"id" => id}} = json_response(conn, 201)

    conn =
      vocab_conn(token)
      |> patch("/api/vocab/entries/#{id}", %{
        "data" => %{
          "type" => "vocab-entry",
          "id" => id,
          "attributes" => %{"note" => "updated note"}
        }
      })

    assert %{"data" => %{"attributes" => %{"note" => "updated note"}}} =
             json_response(conn, 200)

    conn =
      vocab_conn(token)
      |> patch("/api/vocab/entries/#{id}", %{
        "data" => %{
          "type" => "vocab-entry",
          "id" => id,
          "attributes" => %{"lookup_text" => "changed"}
        }
      })

    assert conn.status == 400

    query = Ash.Query.filter(Eim.Vocab.Entry, id == ^id)
    assert {:ok, [entry]} = Ash.read(query, domain: Eim.Vocab, actor: user)
    assert entry.lookup_text == "gave"
    assert entry.note == "updated note"

    conn =
      vocab_conn(token)
      |> patch("/api/vocab/entries/#{id}", %{
        "data" => %{
          "type" => "vocab-entry",
          "id" => id,
          "attributes" => %{"note" => nil}
        }
      })

    assert %{"data" => %{"attributes" => %{"note" => nil}}} = json_response(conn, 200)

    conn =
      vocab_conn(token)
      |> delete("/api/vocab/entries/#{id}")

    assert conn.status == 200
    assert {:ok, []} = Ash.read(query, domain: Eim.Vocab, actor: user)
  end

  test "users cannot update or delete another user's entry", %{token: token} do
    other_user = create_user("other-entry-owner@example.com")

    {:ok, entry} =
      Ash.create(Eim.Vocab.Entry, entry_attributes("other", "other", nil),
        action: :create,
        domain: Eim.Vocab,
        actor: other_user
      )

    conn =
      vocab_conn(token)
      |> patch("/api/vocab/entries/#{entry.id}", %{
        "data" => %{
          "type" => "vocab-entry",
          "id" => entry.id,
          "attributes" => %{"note" => "not allowed"}
        }
      })

    assert conn.status in [403, 404]

    conn =
      vocab_conn(token)
      |> delete("/api/vocab/entries/#{entry.id}")

    assert conn.status in [403, 404]

    assert {:ok, [remaining_entry]} =
             Ash.read(Eim.Vocab.Entry, domain: Eim.Vocab, actor: other_user)

    assert remaining_entry.id == entry.id
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
    assert is_map(spec["paths"]["/api/vocab/entries/{id}"]["patch"])
    assert is_map(spec["paths"]["/api/vocab/entries/{id}"]["delete"])
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

  defp vocab_conn(token) do
    build_conn()
    |> put_req_header("accept", "application/vnd.api+json")
    |> put_req_header("content-type", "application/vnd.api+json")
    |> put_req_header("authorization", "Bearer " <> token)
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
