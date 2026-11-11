defmodule EimWeb.VocabLiveTest do
  use EimWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Eim.Accounts
  alias Eim.Vocab.Entry

  test "requires a web login to access the learning center", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, "/learn/vocab")

    conn = get(build_conn(), "/learn/vocab?entry_id=entry-id&sort=asc")
    assert get_session(conn, :return_to) == "/learn/vocab?entry_id=entry-id&sort=asc"
  end

  test "links to dictionary from the header and the vocabulary page", %{conn: conn} do
    user = create_user("vocab-dictionary-navigation@example.com")
    signed_in = signed_in_conn(conn, user)
    {:ok, view, _} = live(signed_in, "/learn/vocab")

    assert has_element?(
             view,
             "nav[aria-label='Main navigation'] #vocabulary-link + #dictionary-link[href='/dicts/ecdict']"
           )

    assert has_element?(view, "#vocab-workspace #vocab-dictionary-link[href='/dicts/ecdict']")
    assert has_element?(view, "#vocab-workspace #vocab-subtitle", "Your saved words and notes")

    {:ok, dictionary, _} =
      view |> element("#vocab-dictionary-link") |> render_click() |> follow_redirect(signed_in)

    assert has_element?(dictionary, "#ecdict-workspace")
  end

  test "dictionary remains available in the header when signed out", %{conn: conn} do
    {:ok, view, _} = live(conn, "/dicts/ecdict")

    assert has_element?(
             view,
             "nav[aria-label='Main navigation'] #dictionary-link[href='/dicts/ecdict']"
           )

    refute has_element?(view, "#vocabulary-link")
  end

  test "opens an owned entry from a learning-center deep link", %{conn: conn} do
    user = create_user("vocab-live-deep-link@example.com")
    entries = for index <- 1..11, do: create_entry(user, "linked#{index}")
    entry = hd(entries)
    old_date = DateTime.add(DateTime.utc_now(), -86_400, :second)

    Eim.Repo.update_all(
      from(vocab_entry in Entry, where: vocab_entry.id == ^entry.id),
      set: [inserted_at: old_date, updated_at: old_date]
    )

    {:ok, view, _html} =
      live(signed_in_conn(conn, user), "/learn/vocab?entry_id=#{entry.id}")

    assert has_element?(view, "#vocab-detail-panel")
    assert has_element?(view, "#vocab-detail-title", "linked")
    assert has_element?(view, "#{entry_selector(entry.id)}[aria-current='true']")
    assert has_element?(view, "#vocab-collected-#{entry.id}")

    view
    |> element("#vocab-detail-close")
    |> render_click()

    refute has_element?(view, "#vocab-detail-panel")
  end

  test "does not open another user's entry from a learning-center deep link", %{conn: conn} do
    user = create_user("vocab-live-link-owner@example.com")
    other_user = create_user("vocab-live-link-other@example.com")
    entry = create_entry(other_user, "private")

    {:ok, view, _html} =
      live(signed_in_conn(conn, user), "/learn/vocab?entry_id=#{entry.id}")

    refute has_element?(view, "#vocab-detail-panel")
    refute has_element?(view, entry_selector(entry.id))
  end

  test "list shows phonetic, first available meaning, note and collection date", %{conn: conn} do
    user = create_user("vocab-list-summary@example.com")

    entry =
      create_entry(user, "give", %{
        phonetic: "ɡɪv",
        note: "A personal reminder",
        dictionary_snapshot: %{
          "senses" => [
            %{"zh" => ""},
            %{"pos" => "v", "zh" => "给"},
            %{"pos" => "n", "zh" => "弹性"}
          ]
        }
      })

    missing = create_entry(user, "missing")
    collected_at = ~U[2024-02-03 04:05:06Z]

    Eim.Repo.update_all(
      from(vocab_entry in Entry, where: vocab_entry.id == ^entry.id),
      set: [inserted_at: collected_at]
    )

    {:ok, view, _} = live(signed_in_conn(conn, user), "/learn/vocab")

    assert has_element?(view, entry_selector(entry.id), "ɡɪv")
    assert has_element?(view, "#vocab-list-meaning-#{entry.id}", "v 给")
    refute has_element?(view, "#vocab-list-meaning-#{entry.id}", "弹性")
    assert has_element?(view, "#vocab-list-note-#{entry.id}", "A personal reminder")

    assert has_element?(
             view,
             "#vocab-list-collected-#{entry.id}[datetime^='2024-02-03T04:05:06']",
             "Feb 03, 2024"
           )

    assert has_element?(view, "#vocab-list-meaning-#{missing.id}", "No saved definition")
    assert has_element?(view, "#vocab-list-note-#{missing.id}", "No personal note")

    view |> element(entry_selector(entry.id)) |> render_click()

    view
    |> element("#vocab-note-form-#{entry.id}")
    |> render_change(%{"entry_note" => %{"note" => "Updated note"}})

    assert has_element?(view, "#vocab-list-note-#{entry.id}", "Updated note")
    assert has_element?(view, "#vocab-list-meaning-#{entry.id}", "v 给")
    assert has_element?(view, "#vocab-list-collected-#{entry.id}", "Feb 03, 2024")
  end

  test "shows only the current user's entries and offers 10, 20, and 30 item pages", %{
    conn: conn
  } do
    user = create_user("vocab-live-user@example.com")
    other_user = create_user("vocab-live-other@example.com")
    entries = for index <- 1..31, do: create_entry(user, "word#{index}")
    other_entry = create_entry(other_user, "private-word")

    {:ok, view, _html} = live(signed_in_conn(conn, user), "/learn/vocab")

    assert has_element?(view, "#vocab-entry-count", "Showing 1–10 of 31")
    assert has_element?(view, "#vocab-pagination-form #filters_per_page")
    refute has_element?(view, "#vocab-search-form #filters_per_page")
    assert has_element?(view, "#filters_q[placeholder='Hit words you love...']")
    assert has_element?(view, "#vocab-search-hits", "31 words")
    assert has_element?(view, "#vocab-sort-form #filters_sort")
    refute has_element?(view, "#vocab-search-form #filters_sort")
    visible_entries = Enum.count(entries, &has_element?(view, entry_selector(&1.id)))
    visible_entry = Enum.find(entries, &has_element?(view, entry_selector(&1.id)))
    assert visible_entries == 10
    assert has_element?(view, "#vocab-entry-list")
    assert has_element?(view, "#vocab-workspace")
    assert has_element?(view, "#vocab-shortcuts-open")

    view
    |> element("#vocab-shortcuts-open")
    |> render_click()

    assert has_element?(view, "#vocab-shortcuts-dialog")
    assert has_element?(view, "#vocab-shortcuts-dialog", "Select next word")
    assert has_element?(view, "#vocab-shortcuts-dialog", "j / ↓")
    assert has_element?(view, "#vocab-shortcuts-dialog", "k / ↑")
    assert has_element?(view, "#vocab-shortcuts-dialog", "Next page")
    assert has_element?(view, "#vocab-shortcuts-dialog", "Previous page")
    assert has_element?(view, "#vocab-shortcuts-dialog", "Select first word")
    assert has_element?(view, "#vocab-shortcuts-dialog", "Select last word")
    assert has_element?(view, "#vocab-shortcuts-dialog", "Focus selected word's note")
    assert has_element?(view, "#vocab-shortcuts-dialog", "Exit field or close this guide")

    view
    |> element("#vocab-shortcuts-backdrop")
    |> render_click()

    refute has_element?(view, "#vocab-shortcuts-dialog")

    view |> element("#vocab-shortcuts-open") |> render_click()
    view |> element("#vocab-shortcuts-close") |> render_click()
    refute has_element?(view, "#vocab-shortcuts-dialog")

    view
    |> element(entry_selector(visible_entry.id))
    |> render_click()

    assert has_element?(view, "#vocab-detail-panel")
    assert has_element?(view, "#vocab-list-pane #vocab-sort-form")
    assert has_element?(view, "#vocab-list-pane #vocab-entry-list")
    assert has_element?(view, "#vocab-detail-panel[class*='lg:row-start-1']")
    refute has_element?(view, "#vocab-detail-panel[class*='lg:row-start-2']")
    assert has_element?(view, "#vocab-collected-#{visible_entry.id}")
    assert has_element?(view, "#vocab-note-form-#{visible_entry.id}")
    assert has_element?(view, "#{entry_selector(visible_entry.id)}[aria-current='true']")

    view
    |> element("#vocab-detail-close")
    |> render_click()

    refute has_element?(view, "#vocab-detail-panel")

    assert has_element?(view, "button#vocab-page-previous[disabled]")
    refute has_element?(view, entry_selector(other_entry.id))
    assert has_element?(view, "#filters_per_page option[value='10']")
    assert has_element?(view, "#filters_per_page option[value='20']")
    assert has_element?(view, "#filters_per_page option[value='30']")

    view
    |> element("#vocab-pagination-form")
    |> render_change(%{"filters" => %{"q" => "", "sort" => "desc", "per_page" => "20"}})

    assert Enum.count(entries, &has_element?(view, entry_selector(&1.id))) == 20
    assert has_element?(view, "a#vocab-page-next")

    view
    |> element("#vocab-pagination-form")
    |> render_change(%{"filters" => %{"q" => "", "sort" => "desc", "per_page" => "30"}})

    assert Enum.count(entries, &has_element?(view, entry_selector(&1.id))) == 30

    view
    |> element("#vocab-page-next")
    |> render_click()

    assert Enum.count(entries, &has_element?(view, entry_selector(&1.id))) == 1
    assert has_element?(view, "button#vocab-page-next[disabled]")
    assert has_element?(view, "a#vocab-page-previous")

    view
    |> element("#vocab-page-previous")
    |> render_click()

    assert Enum.count(entries, &has_element?(view, entry_selector(&1.id))) == 30
  end

  test "filters entries and sorts by updated_at in either direction", %{conn: conn} do
    user = create_user("vocab-live-sort@example.com")
    older_entry = create_entry(user, "older")
    newer_entry = create_entry(user, "newer")
    now = DateTime.utc_now()

    Eim.Repo.update_all(
      from(entry in Entry, where: entry.id == ^older_entry.id),
      set: [updated_at: DateTime.add(now, -7200, :second)]
    )

    Eim.Repo.update_all(
      from(entry in Entry, where: entry.id == ^newer_entry.id),
      set: [updated_at: DateTime.add(now, -3600, :second)]
    )

    {:ok, view, _html} = live(signed_in_conn(conn, user), "/learn/vocab")

    html = render(view)
    assert html_position(html, newer_entry.id) < html_position(html, older_entry.id)

    view
    |> element("#vocab-sort-form")
    |> render_change(%{"filters" => %{"q" => "", "sort" => "asc", "per_page" => "10"}})

    html = render(view)
    assert html_position(html, older_entry.id) < html_position(html, newer_entry.id)

    view
    |> element(entry_selector(older_entry.id))
    |> render_click()

    view
    |> element("#vocab-note-form-#{older_entry.id}")
    |> render_change(%{"entry_note" => %{"note" => "reviewed today"}})

    assert has_element?(view, "#vocab-note-saved-#{older_entry.id}")

    view
    |> element("#vocab-note-input-#{older_entry.id}")
    |> render_blur(%{"value" => "reviewed today"})

    assert has_element?(view, "#vocab-note-form-#{older_entry.id}")

    view
    |> element("#vocab-detail-close")
    |> render_click()

    view
    |> element("#vocab-search-form")
    |> render_change(%{"filters" => %{"q" => "", "sort" => "desc", "per_page" => "10"}})

    html = render(view)
    assert html_position(html, older_entry.id) < html_position(html, newer_entry.id)

    view
    |> element("#vocab-search-form")
    |> render_change(%{"filters" => %{"q" => "older", "sort" => "asc", "per_page" => "10"}})

    assert has_element?(view, entry_selector(older_entry.id))
    refute has_element?(view, entry_selector(newer_entry.id))
    assert has_element?(view, "#vocab-search-hits", "1 match")
    assert has_element?(view, "#filters_sort option[selected][value='asc']")

    view
    |> element("#vocab-search-form")
    |> render_change(%{
      "filters" => %{"q" => "no-such-word", "sort" => "asc", "per_page" => "10"}
    })

    assert has_element?(view, "#vocab-no-results")

    view
    |> element("#vocab-clear-search")
    |> render_click()

    assert has_element?(view, entry_selector(older_entry.id))
  end

  test "edits, clears, and deletes the user's own vocabulary entry", %{conn: conn} do
    user = create_user("vocab-live-edit@example.com")
    entry = create_entry(user, "remember")
    {:ok, view, _html} = live(signed_in_conn(conn, user), "/learn/vocab")

    view
    |> element(entry_selector(entry.id))
    |> render_click()

    view
    |> element("#vocab-note-form-#{entry.id}")
    |> render_change(%{"entry_note" => %{"note" => "draft"}})

    assert has_element?(view, "#vocab-note-count-#{entry.id}", "5")
    assert has_element?(view, "#vocab-note-saved-#{entry.id}")
    assert has_element?(view, "#vocab-detail-panel")
    assert {:ok, [saved_entry]} = Ash.read(Entry, domain: Eim.Vocab, actor: user)
    assert saved_entry.note == "draft"

    view
    |> element("#vocab-note-form-#{entry.id}")
    |> render_change(%{"entry_note" => %{"note" => "a personal reminder"}})

    assert has_element?(view, "#vocab-note-saved-#{entry.id}")

    view
    |> element("#vocab-note-input-#{entry.id}")
    |> render_blur(%{"value" => "a personal reminder"})

    assert has_element?(view, "#vocab-note-form-#{entry.id}")

    view |> element("#vocab-detail-close") |> render_click()

    view
    |> element(entry_selector(entry.id))
    |> render_click()

    view
    |> element("#vocab-note-form-#{entry.id}")
    |> render_change(%{"entry_note" => %{"note" => ""}})

    assert {:ok, [saved_entry]} = Ash.read(Entry, domain: Eim.Vocab, actor: user)
    assert saved_entry.note == nil

    view
    |> element("#vocab-note-input-#{entry.id}")
    |> render_blur(%{"value" => ""})

    assert has_element?(view, "#vocab-note-form-#{entry.id} textarea", "")

    view
    |> element("#vocab-delete-ask-#{entry.id}")
    |> render_click()

    assert has_element?(view, "#vocab-delete-confirm-#{entry.id}")

    view
    |> element("#vocab-delete-#{entry.id}")
    |> render_click()

    refute has_element?(view, entry_selector(entry.id))
    assert has_element?(view, "#vocab-empty-state")
    assert {:ok, []} = Ash.read(Entry, domain: Eim.Vocab, actor: user)
  end

  test "preserves note text and shows an error when the note exceeds the limit", %{conn: conn} do
    user = create_user("vocab-live-limit@example.com")
    entry = create_entry(user, "limit")
    {:ok, view, _html} = live(signed_in_conn(conn, user), "/learn/vocab")

    view
    |> element(entry_selector(entry.id))
    |> render_click()

    oversized_note = String.duplicate("x", 2001)

    view
    |> element("#vocab-note-form-#{entry.id}")
    |> render_change(%{"entry_note" => %{"note" => oversized_note}})

    assert has_element?(view, "#vocab-note-error-#{entry.id}")
    assert has_element?(view, "#vocab-note-form-#{entry.id} textarea", oversized_note)
    assert {:ok, [saved_entry]} = Ash.read(Entry, domain: Eim.Vocab, actor: user)
    assert saved_entry.note == nil
  end

  defp create_user(email) do
    {:ok, hashed_password} = AshAuthentication.BcryptProvider.hash("password123456")

    Ash.Seed.seed!(Accounts.User, %{
      email: email,
      hashed_password: hashed_password,
      confirmed_at: DateTime.utc_now()
    })
  end

  defp create_entry(user, term, attrs \\ %{}) do
    {:ok, entry} =
      Ash.create(
        Entry,
        Map.merge(
          %{
            lookup_text: term,
            lemma: term,
            dictionary_snapshot: %{"senses" => []},
            note: nil
          },
          attrs
        ),
        action: :create,
        domain: Eim.Vocab,
        actor: user
      )

    entry
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

  defp html_position(html, id) do
    {position, _length} = :binary.match(html, "data-vocab-entry=\"#{id}\"")
    position
  end

  defp entry_selector(id), do: "#vocab-entry-list [data-vocab-entry='#{id}']"
end
