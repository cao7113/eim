defmodule EimWeb.EcdictLiveTest do
  use EimWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Eim.Accounts
  alias Eim.Dict.{Importer, Lexeme}
  alias Eim.Vocab.Entry

  @fixture Path.expand("../support/fixtures/ecdict_sample.csv", __DIR__)

  setup do
    Importer.run(@fixture)
    :ok
  end

  test "public search finds both source entries and word forms without duplicates", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dicts/ecdict")

    assert has_element?(view, "#ecdict-search-form")
    assert has_element?(view, "#ecdict-import-info", "Last import: 4 rows processed")

    view
    |> form("#ecdict-search-form", search: %{q: "GAVE"})
    |> render_submit()

    assert_patch(view, "/dicts/ecdict?q=GAVE")
    assert has_element?(view, "#ecdict-entries a", "gave")
    assert has_element?(view, "#ecdict-entries a", "give")
    refute has_element?(view, "#ecdict-entries a", "running")

    view
    |> form("#ecdict-search-form", search: %{q: "not-a-word"})
    |> render_submit()

    assert has_element?(view, "#ecdict-empty", "No entries found")
    assert has_element?(view, "#ecdict-previous[disabled]")
    assert has_element?(view, "#ecdict-next[disabled]")
  end

  test "public detail preserves the source and omits unavailable fields", %{conn: conn} do
    lexeme = Eim.Repo.one!(from l in Lexeme, where: l.word == "give")
    {:ok, view, _html} = live(conn, "/dicts/ecdict/#{lexeme.id}?q=gave")

    assert has_element?(view, "#ecdict-detail-word", "give")
    assert has_element?(view, "#ecdict-translation", "给")
    assert has_element?(view, "#ecdict-definition")
    assert has_element?(view, "#ecdict-forms", "gave")
    assert has_element?(view, "#ecdict-back[href='/dicts/ecdict?q=gave']")
    assert has_element?(view, "#ecdict-sign-in[href='/dicts/ecdict/#{lexeme.id}/sign-in?q=gave']")

    missing = Eim.Repo.one!(from l in Lexeme, where: l.word == "gave")
    {:ok, missing_view, _html} = live(build_conn(), "/dicts/ecdict/#{missing.id}")
    refute has_element?(missing_view, "#ecdict-definition")
    assert has_element?(missing_view, "#ecdict-no-forms")
  end

  test "invalid links and searches show explicit errors", %{conn: conn} do
    {:ok, invalid_view, _html} = live(conn, "/dicts/ecdict/not-a-uuid")
    assert has_element?(invalid_view, "#ecdict-error", "could not be found")

    {:ok, cursor_view, _html} = live(build_conn(), "/dicts/ecdict?cursor=invalid")
    assert has_element?(cursor_view, "#ecdict-error", "invalid")

    {:ok, search_view, _html} =
      live(build_conn(), "/dicts/ecdict?q=#{String.duplicate("x", 501)}")

    assert has_element?(search_view, "#ecdict-error", "500 characters")

    {:ok, category_view, _html} = live(build_conn(), "/dicts/ecdict?category=root")
    assert has_element?(category_view, "#ecdict-error", "category is invalid")
  end

  test "live prefix search and category preserve filtering in detail and sign-in links", %{
    conn: conn
  } do
    now = DateTime.utc_now()

    Eim.Repo.insert_all("lexemes", [
      %{
        word: "give away",
        word_lc: "give away",
        sw: "giveaway",
        source: "ecdict",
        inserted_at: now,
        updated_at: now
      },
      %{
        word: "give-",
        word_lc: "give-",
        sw: "give",
        source: "ecdict",
        inserted_at: now,
        updated_at: now
      }
    ])

    {:ok, view, _} = live(conn, "/dicts/ecdict")
    view |> form("#ecdict-search-form", search: %{q: "giv"}) |> render_change()
    assert_patch(view, "/dicts/ecdict?q=giv")
    assert has_element?(view, "#ecdict-entries a", "give away")
    view |> element("#ecdict-category-phrase") |> render_click()
    assert_patch(view, "/dicts/ecdict?category=phrase&q=giv")
    assert has_element?(view, "#ecdict-category-phrase[aria-pressed=true]")
    assert has_element?(view, "#ecdict-entries a", "give away")
    refute has_element?(view, "#ecdict-entries a", "give-")
    view |> element("#ecdict-entries a", "give away") |> render_click()
    assert has_element?(view, "#ecdict-detail-word", "give away")
    assert has_element?(view, "#ecdict-back[href*='category=phrase']")
    assert has_element?(view, "#ecdict-sign-in[href*='category=phrase']")
    view |> form("#ecdict-search-form", search: %{q: "xyz"}) |> render_change()
    assert_patch(view, "/dicts/ecdict?category=phrase&q=xyz")
    assert has_element?(view, "#ecdict-empty")
  end

  test "separately filters words, phrases, prefixes, suffixes, compounds and other entries", %{
    conn: conn
  } do
    now = DateTime.utc_now()

    for word <- [
          "address",
          "address book",
          "address-book",
          "address-",
          "-address",
          "address1",
          "A.B.G."
        ] do
      Eim.Repo.insert_all("lexemes", [
        %{
          word: word,
          word_lc: String.downcase(word),
          sw: word,
          source: "ecdict",
          inserted_at: now,
          updated_at: now
        }
      ])
    end

    {:ok, view, _} = live(conn, "/dicts/ecdict")

    for {category, word} <- [
          {"word", "address"},
          {"phrase", "address book"},
          {"prefix", "address-"},
          {"suffix", "-address"},
          {"compound", "address-book"},
          {"abbreviation", "A.B.G."},
          {"other", "address1"}
        ] do
      view |> element("#ecdict-category-#{category}") |> render_click()
      assert_patch(view, "/dicts/ecdict?category=#{category}")
      assert has_element?(view, "#ecdict-category-#{category}[aria-pressed=true]")
      assert has_element?(view, "#ecdict-entries a", word)
    end

    view |> element("#ecdict-entries a", "address1") |> render_click()
    assert has_element?(view, "#ecdict-back[href*='category=other']")
    assert has_element?(view, "#ecdict-sign-in[href*='category=other']")
  end

  test "abbreviation filter retains search and detail links", %{conn: conn} do
    now = DateTime.utc_now()

    Eim.Repo.insert_all("lexemes", [
      %{
        word: "A.B.G.",
        word_lc: "a.b.g.",
        sw: "abg",
        source: "ecdict",
        inserted_at: now,
        updated_at: now
      },
      %{
        word: "6.2",
        word_lc: "6.2",
        sw: "62",
        source: "ecdict",
        inserted_at: now,
        updated_at: now
      }
    ])

    {:ok, view, _} = live(conn, "/dicts/ecdict")
    view |> element("#ecdict-category-abbreviation") |> render_click()
    assert_patch(view, "/dicts/ecdict?category=abbreviation")
    assert has_element?(view, "#ecdict-entries a", "A.B.G.")
    refute has_element?(view, "#ecdict-entries a", "6.2")
    view |> form("#ecdict-search-form", search: %{q: "a.b"}) |> render_change()
    assert_patch(view, "/dicts/ecdict?category=abbreviation&q=a.b")
    view |> element("#ecdict-entries a", "A.B.G.") |> render_click()
    assert has_element?(view, "#ecdict-detail-word", "A.B.G.")
    assert has_element?(view, "#ecdict-back[href*='category=abbreviation']")
    assert has_element?(view, "#ecdict-sign-in[href*='category=abbreviation']")
  end

  test "list pagination works in both directions and keeps list state in detail links", %{
    conn: conn
  } do
    now = DateTime.utc_now()

    rows =
      for index <- 1..25 do
        word = "word#{String.pad_leading(Integer.to_string(index), 2, "0")}"

        %{
          word: word,
          word_lc: word,
          sw: word,
          source: "ecdict",
          inserted_at: now,
          updated_at: now
        }
      end

    Eim.Repo.insert_all("lexemes", rows)
    {:ok, view, _html} = live(conn, "/dicts/ecdict?q=word&category=other")
    assert has_element?(view, "a#ecdict-next")
    assert has_element?(view, "button#ecdict-previous[disabled]")
    assert has_element?(view, "#ecdict-previous .hero-arrow-left")
    assert has_element?(view, "#ecdict-next .hero-arrow-right")
    assert has_element?(view, "#ecdict-next[href*='q=word'][href*='category=other']")

    assert view
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("#ecdict-entries a")
           |> Enum.count() == 10

    view |> element("#ecdict-next") |> render_click()
    assert has_element?(view, "a#ecdict-previous")

    assert has_element?(
             view,
             "#ecdict-entries a[href*='cursor='][href*='q=word'][href*='category=other']"
           )

    assert has_element?(view, "#ecdict-previous[href*='q=word'][href*='category=other']")
    assert has_element?(view, "a#ecdict-next")

    view |> element("#ecdict-next") |> render_click()
    assert has_element?(view, "button#ecdict-next[disabled]")

    view |> element("#ecdict-previous") |> render_click()
    assert has_element?(view, "#ecdict-previous")
    view |> element("#ecdict-previous") |> render_click()
    assert has_element?(view, "button#ecdict-previous[disabled]")
    assert has_element?(view, "a#ecdict-next")
  end

  test "selecting words patches the detail, retains search, and supports the shortcut guide", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/dicts/ecdict?q=gave")
    give = Eim.Repo.one!(from l in Lexeme, where: l.word == "give")
    gave = Eim.Repo.one!(from l in Lexeme, where: l.word == "gave")
    assert has_element?(view, "#ecdict-detail-placeholder")
    view |> element("[data-ecdict-entry='#{give.id}']") |> render_click()
    assert_patch(view, "/dicts/ecdict/#{give.id}?q=gave")
    assert has_element?(view, "#ecdict-detail-word", "give")
    assert has_element?(view, "[data-ecdict-entry='#{give.id}'][aria-current='true']")
    view |> element("[data-ecdict-entry='#{gave.id}']") |> render_click()
    assert has_element?(view, "#ecdict-detail-word", "gave")
    assert has_element?(view, "[data-ecdict-entry='#{gave.id}'][aria-current='true']")
    refute has_element?(view, "[data-ecdict-entry='#{give.id}'][aria-current='true']")
    view |> element("#ecdict-shortcuts-open") |> render_click()
    assert has_element?(view, "#ecdict-shortcuts-dialog", "Select next word")
    assert has_element?(view, "#ecdict-shortcuts-dialog", "j / ↓")
    assert has_element?(view, "#ecdict-shortcuts-dialog", "k / ↑")
    assert has_element?(view, "#ecdict-shortcuts-dialog", "Next page")
    assert has_element?(view, "#ecdict-shortcuts-dialog", "Previous page")
    view |> element("#ecdict-shortcuts-backdrop") |> render_click()
    refute has_element?(view, "#ecdict-shortcuts-dialog")
    view |> element("#ecdict-shortcuts-open") |> render_click()
    view |> element("#ecdict-shortcuts-close") |> render_click()
    refute has_element?(view, "#ecdict-shortcuts-dialog")
    view |> element("#ecdict-back") |> render_click()
    assert_patch(view, "/dicts/ecdict?q=gave")
    assert has_element?(view, "#ecdict-detail-placeholder")
  end

  test "sign-in after live navigation returns to the selected entry", %{conn: conn} do
    lexeme = Eim.Repo.one!(from l in Lexeme, where: l.word == "give")
    conn = get(conn, "/dicts/ecdict/#{lexeme.id}/sign-in?q=gave")
    assert redirected_to(conn) == "/sign-in"
    assert get_session(conn, :return_to) == "/dicts/ecdict/#{lexeme.id}?q=gave"
  end

  test "anonymous entry visits preserve the return path through sign-in", %{conn: conn} do
    lexeme = Eim.Repo.one!(from l in Lexeme, where: l.word == "give")
    conn = get(conn, "/dicts/ecdict/#{lexeme.id}?q=gave")
    assert get_session(conn, :return_to) == "/dicts/ecdict/#{lexeme.id}?q=gave"
  end

  test "saving is user-scoped and does not overwrite existing notes or snapshots", %{conn: conn} do
    user = create_user("ecdict-owner@example.com")
    other_user = create_user("ecdict-other@example.com")
    lexeme = Eim.Repo.one!(from l in Lexeme, where: l.word == "give")
    {:ok, view, _html} = live(signed_in_conn(conn, user), "/dicts/ecdict/#{lexeme.id}")

    assert has_element?(view, "#ecdict-detail-actions #ecdict-save")
    view |> element("#ecdict-save") |> render_click()
    assert {:ok, [saved]} = Ash.read(Entry, domain: Eim.Vocab, actor: user)

    assert has_element?(
             view,
             "#ecdict-detail-actions #ecdict-saved-link[href='/learn/vocab?entry_id=#{saved.id}']"
           )

    refute has_element?(view, "#ecdict-save")
    assert saved.dictionary_snapshot["sources"] |> hd() |> Map.get("entry_id") == lexeme.id
    assert {:ok, []} = Ash.read(Entry, domain: Eim.Vocab, actor: other_user)

    assert {:ok, _} =
             Ash.update(saved, %{note: "Keep this"},
               action: :update_note,
               domain: Eim.Vocab,
               actor: user
             )

    render_hook(view, "save", %{})
    assert {:ok, [saved_again]} = Ash.read(Entry, domain: Eim.Vocab, actor: user)
    assert saved_again.id == saved.id
    assert saved_again.note == "Keep this"
    assert saved_again.dictionary_snapshot == saved.dictionary_snapshot
  end

  test "previously saved entries are detected on load and only for their owner", %{conn: conn} do
    user = create_user("ecdict-saved-owner@example.com")
    other_user = create_user("ecdict-saved-viewer@example.com")
    lexeme = Eim.Repo.one!(from l in Lexeme, where: l.word == "give")
    gave = Eim.Repo.one!(from l in Lexeme, where: l.word == "gave")

    {:ok, saved} =
      Ash.create(
        Entry,
        %{
          lookup_text: "ＧＩＶＥ",
          lemma: "ＧＩＶＥ",
          dictionary_snapshot: %{"senses" => []},
          note: "My note"
        },
        action: :create,
        domain: Eim.Vocab,
        actor: user
      )

    {:ok, view, _} = live(signed_in_conn(conn, user), "/dicts/ecdict/#{lexeme.id}?q=gave")
    assert has_element?(view, "#ecdict-saved-link[href='/learn/vocab?entry_id=#{saved.id}']")
    refute has_element?(view, "#ecdict-save")

    view |> element("[data-ecdict-entry='#{gave.id}']") |> render_click()
    assert has_element?(view, "#ecdict-save")
    refute has_element?(view, "#ecdict-saved-link")
    view |> element("[data-ecdict-entry='#{lexeme.id}']") |> render_click()
    assert has_element?(view, "#ecdict-saved-link[href='/learn/vocab?entry_id=#{saved.id}']")

    {:ok, other_view, _} =
      live(signed_in_conn(build_conn(), other_user), "/dicts/ecdict/#{lexeme.id}")

    assert has_element?(other_view, "#ecdict-save")
    refute has_element?(other_view, "#ecdict-saved-link")

    {:ok, anonymous_view, _} = live(build_conn(), "/dicts/ecdict/#{lexeme.id}")
    assert has_element?(anonymous_view, "#ecdict-sign-in")
    refute has_element?(anonymous_view, "#ecdict-saved-link")
  end

  test "saved link opens the exact vocabulary entry", %{conn: conn} do
    user = create_user("ecdict-saved-link@example.com")
    lexeme = Eim.Repo.one!(from l in Lexeme, where: l.word == "give")
    signed_in = signed_in_conn(conn, user)
    {:ok, view, _} = live(signed_in, "/dicts/ecdict/#{lexeme.id}")
    view |> element("#ecdict-save") |> render_click()
    assert {:ok, [saved]} = Ash.read(Entry, domain: Eim.Vocab, actor: user)

    {:ok, vocab_view, _} =
      view |> element("#ecdict-saved-link") |> render_click() |> follow_redirect(signed_in)

    assert has_element?(vocab_view, "#vocab-detail-panel")

    assert has_element?(
             vocab_view,
             "#vocab-entry-list [data-vocab-entry='#{saved.id}'][aria-current='true']"
           )
  end

  defp create_user(email) do
    {:ok, hashed_password} = AshAuthentication.BcryptProvider.hash("password123456")

    Ash.Seed.seed!(Accounts.User, %{
      email: email,
      hashed_password: hashed_password,
      confirmed_at: DateTime.utc_now()
    })
  end

  defp signed_in_conn(conn, user) do
    strategy = AshAuthentication.Info.strategy!(Accounts.User, :password)

    {:ok, signed_in_user} =
      AshAuthentication.Strategy.action(strategy, :sign_in, %{
        email: to_string(user.email),
        password: "password123456"
      })

    conn
    |> init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(signed_in_user)
  end
end
