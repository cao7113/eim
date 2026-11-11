defmodule EimWeb.VocabLive do
  use EimWeb, :live_view

  require Ash.Query
  require Logger

  alias Eim.Vocab.Entry

  @per_page_options [10, 20, 30]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Vocabulary",
       search: "",
       filter_form: to_form(%{"q" => "", "sort" => "desc", "per_page" => "10"}, as: :filters),
       sort: "desc",
       per_page: 10,
       page: 1,
       page_count: 1,
       total_count: 0,
       deep_link_entry_id: nil,
       load_error: nil,
       selected_id: nil,
       selected_entry: nil,
       editing_id: nil,
       note_form: nil,
       note_count: 0,
       note_error: nil,
       note_saved: false,
       delete_id: nil,
       shortcuts_open: false
     )
     |> stream(:entries, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    search = params |> Map.get("q", "") |> normalize_search()
    sort = if Map.get(params, "sort") == "asc", do: "asc", else: "desc"
    per_page = parse_per_page(Map.get(params, "per_page"))
    page = parse_page(Map.get(params, "page"))
    deep_link_entry_id = params |> Map.get("entry_id") |> valid_entry_id()
    selected_entry = load_deep_link_entry(deep_link_entry_id, socket.assigns.current_user)

    socket =
      assign(socket,
        search: search,
        sort: sort,
        per_page: per_page,
        deep_link_entry_id: deep_link_entry_id,
        filter_form:
          to_form(
            %{"q" => search, "sort" => sort, "per_page" => to_string(per_page)},
            as: :filters
          ),
        selected_id: nil,
        selected_entry: nil,
        editing_id: nil,
        note_form: nil,
        note_count: 0,
        note_error: nil,
        note_saved: false,
        delete_id: nil,
        shortcuts_open: false
      )

    case load_entries(socket.assigns.current_user, search, sort, per_page, page) do
      {:ok, entries, total_count, page_count, actual_page} ->
        entries = pin_selected_entry(entries, selected_entry, per_page)

        socket =
          socket
          |> assign(
            page: actual_page,
            page_count: page_count,
            total_count: total_count,
            load_error: nil,
            selected_id: selected_entry && selected_entry.id,
            selected_entry: selected_entry,
            editing_id: selected_entry && selected_entry.id,
            note_form: selected_entry && note_form(selected_entry.note),
            note_count: if(selected_entry, do: String.length(selected_entry.note || ""), else: 0)
          )
          |> stream(:entries, entries, reset: true)

        socket =
          if deep_link_entry_id && is_nil(selected_entry) do
            put_flash(socket, :error, "That vocabulary entry is unavailable.")
          else
            socket
          end

        if actual_page != page do
          {:noreply, push_patch(socket, to: vocab_path(search, sort, per_page, actual_page))}
        else
          {:noreply, socket}
        end

      {:error, _error} ->
        Logger.error("Failed to load vocabulary entries")

        {:noreply,
         socket
         |> assign(
           page: 1,
           page_count: 1,
           total_count: 0,
           load_error: "We couldn't load your vocabulary. Please refresh and try again.",
           selected_id: nil,
           selected_entry: nil
         )
         |> stream(:entries, [], reset: true)}
    end
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    search = filters |> Map.get("q", "") |> normalize_search()
    sort = if Map.get(filters, "sort") == "asc", do: "asc", else: "desc"
    per_page = parse_per_page(Map.get(filters, "per_page"))

    {:noreply,
     push_patch(socket,
       to: vocab_path(search, sort, per_page, 1)
     )}
  end

  def handle_event("select-entry", %{"id" => id}, socket) do
    previous_id = socket.assigns.selected_id

    case get_owned_entry(id, socket.assigns.current_user) do
      {:ok, entry} ->
        socket =
          socket
          |> assign(
            selected_id: id,
            selected_entry: entry,
            editing_id: id,
            note_form: note_form(entry.note),
            note_count: String.length(entry.note || ""),
            note_error: nil,
            note_saved: false,
            delete_id: nil
          )

        socket =
          socket
          |> stream_entry(previous_id)
          |> stream_entry(id)

        {:noreply, socket}

      :error ->
        {:noreply, put_flash(socket, :error, "That vocabulary entry is unavailable.")}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "We couldn't load that vocabulary entry.")}
    end
  end

  def handle_event("close-details", _params, socket) do
    id = socket.assigns.selected_id

    socket =
      socket
      |> assign(
        selected_id: nil,
        selected_entry: nil,
        editing_id: nil,
        note_form: nil,
        note_count: 0,
        note_error: nil,
        note_saved: false,
        delete_id: nil
      )
      |> stream_entry(id)

    if socket.assigns.deep_link_entry_id do
      {:noreply,
       push_patch(socket,
         to:
           vocab_path(
             socket.assigns.search,
             socket.assigns.sort,
             socket.assigns.per_page,
             socket.assigns.page
           )
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("show-shortcuts", _params, socket) do
    {:noreply, assign(socket, shortcuts_open: true)}
  end

  def handle_event("hide-shortcuts", _params, socket) do
    {:noreply, assign(socket, shortcuts_open: false)}
  end

  def handle_event(
        "autosave-note",
        %{"entry_note" => %{"note" => note}},
        %{assigns: %{editing_id: id}} = socket
      )
      when is_binary(id) do
    save_note(socket, note, false)
  end

  def handle_event("autosave-note", _params, socket), do: {:noreply, socket}

  def handle_event(
        "finish-note",
        %{"value" => note},
        %{assigns: %{editing_id: id}} = socket
      )
      when is_binary(id) do
    save_note(socket, note, true)
  end

  def handle_event("finish-note", _params, socket), do: {:noreply, socket}

  def handle_event("ask-delete", %{"id" => id}, socket) do
    socket =
      assign(socket, delete_id: id)
      |> stream_entry(id)

    {:noreply, socket}
  end

  def handle_event("cancel-delete", _params, socket) do
    id = socket.assigns.delete_id
    socket = socket |> assign(delete_id: nil) |> stream_entry(id)
    {:noreply, socket}
  end

  def handle_event("delete-entry", %{"id" => id}, socket) do
    if socket.assigns.delete_id == id do
      case get_owned_entry(id, socket.assigns.current_user) do
        {:ok, entry} ->
          case Ash.destroy(entry,
                 action: :destroy,
                 domain: Eim.Vocab,
                 actor: socket.assigns.current_user
               ) do
            :ok ->
              socket =
                socket
                |> assign(
                  delete_id: nil,
                  selected_id: nil,
                  selected_entry: nil,
                  editing_id: nil,
                  note_form: nil,
                  note_count: 0,
                  shortcuts_open: false
                )
                |> put_flash(:info, "Vocabulary entry deleted.")

              {:noreply, refresh_entries(socket)}

            {:error, _error} ->
              Logger.error("Failed to delete a vocabulary entry")

              {:noreply,
               put_flash(socket, :error, "We couldn't delete that entry. Please try again.")}
          end

        :error ->
          {:noreply,
           socket
           |> assign(delete_id: nil)
           |> put_flash(:error, "That vocabulary entry is unavailable.")}

        {:error, _error} ->
          {:noreply, put_flash(socket, :error, "We couldn't load that vocabulary entry.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Please confirm the deletion first.")}
    end
  end

  defp load_entries(user, search, sort, per_page, requested_page) do
    query = search_query(search)

    with {:ok, total_count} <-
           Ash.count(query, domain: Eim.Vocab, actor: user),
         page_count <- max(div(total_count + per_page - 1, per_page), 1),
         page <- min(requested_page, page_count),
         direction <- if(sort == "asc", do: :asc, else: :desc),
         query <-
           query
           |> Ash.Query.sort(updated_at: direction, id: direction)
           |> Ash.Query.limit(per_page)
           |> Ash.Query.offset((page - 1) * per_page),
         {:ok, entries} <- Ash.read(query, domain: Eim.Vocab, actor: user) do
      {:ok, entries, total_count, page_count, page}
    end
  end

  defp search_query(search) do
    query = Ash.Query.new(Entry)

    if search == "" do
      query
    else
      pattern = "%" <> escape_like(search) <> "%"

      Ash.Query.filter(
        query,
        ilike(term_key, ^pattern) or ilike(lookup_text, ^pattern) or ilike(lemma, ^pattern)
      )
    end
  end

  defp escape_like(search) do
    search
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp get_owned_entry(id, user) do
    query = Ash.Query.filter(Entry, id == ^id)

    case Ash.read(query, domain: Eim.Vocab, actor: user) do
      {:ok, [entry]} ->
        {:ok, entry}

      {:ok, []} ->
        :error

      {:error, _error} ->
        Logger.error("Failed to load a vocabulary entry")
        {:error, :load_failed}
    end
  end

  defp valid_entry_id(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp valid_entry_id(_id), do: nil

  defp load_deep_link_entry(nil, _user), do: nil

  defp load_deep_link_entry(id, user) do
    case get_owned_entry(id, user) do
      {:ok, entry} -> entry
      :error -> nil
      {:error, _error} -> nil
    end
  end

  defp pin_selected_entry(entries, nil, _per_page), do: entries

  defp pin_selected_entry(entries, selected_entry, per_page) do
    if Enum.any?(entries, &(&1.id == selected_entry.id)) do
      entries
    else
      [selected_entry | Enum.reject(entries, &(&1.id == selected_entry.id))]
      |> Enum.take(per_page)
    end
  end

  defp stream_entry(socket, id) when is_binary(id) do
    case get_owned_entry(id, socket.assigns.current_user) do
      {:ok, entry} ->
        stream_insert(socket, :entries, entry)

      :error ->
        socket

      {:error, _error} ->
        put_flash(socket, :error, "We couldn't refresh that vocabulary entry.")
    end
  end

  defp stream_entry(socket, _id), do: socket

  defp update_note(entry, note, user) do
    case Ash.update(entry, %{note: note},
           action: :update_note,
           domain: Eim.Vocab,
           actor: user
         ) do
      {:ok, updated_entry} ->
        {:ok, updated_entry}

      {:error, %Ash.Error.Invalid{} = error} ->
        {:error, error}

      {:error, error} ->
        Logger.error("Failed to update a vocabulary note")
        {:error, error}
    end
  end

  defp save_note(socket, note, close_after_save?) do
    id = socket.assigns.editing_id
    normalized_note = if note == "", do: nil, else: note

    with id when is_binary(id) <- id,
         {:ok, entry} <- get_owned_entry(id, socket.assigns.current_user),
         {:ok, updated_entry} <-
           maybe_update_note(entry, normalized_note, socket.assigns.current_user) do
      socket =
        assign(socket,
          selected_entry: updated_entry,
          note_form: note_form(note),
          note_count: String.length(note),
          note_error: nil,
          note_saved: true
        )

      if close_after_save? do
        {:noreply, refresh_entries(socket)}
      else
        {:noreply, stream_entry(socket, id)}
      end
    else
      :error ->
        {:noreply, note_save_error(socket, note, "That vocabulary entry is unavailable.")}

      {:error, :load_failed} ->
        {:noreply,
         note_save_error(socket, note, "We couldn't load that vocabulary entry. Try again.")}

      {:error, %Ash.Error.Invalid{}} ->
        {:noreply,
         note_save_error(
           socket,
           note,
           "We couldn't save that note. Check the 2,000-character limit and try again."
         )}

      {:error, _error} ->
        {:noreply, note_save_error(socket, note, "We couldn't save that note. Please try again.")}

      _other ->
        {:noreply, note_save_error(socket, note, "That vocabulary entry is unavailable.")}
    end
  end

  defp maybe_update_note(entry, note, user) do
    if entry.note == note, do: {:ok, entry}, else: update_note(entry, note, user)
  end

  defp note_save_error(socket, note, message) do
    socket =
      assign(socket,
        note_form: note_form(note),
        note_count: String.length(note),
        note_error: message,
        note_saved: false
      )

    stream_entry(socket, socket.assigns.editing_id)
  end

  defp refresh_entries(socket) do
    %{search: search, sort: sort, per_page: per_page, page: page} = socket.assigns

    case load_entries(socket.assigns.current_user, search, sort, per_page, page) do
      {:ok, entries, total_count, page_count, actual_page} ->
        entries = pin_selected_entry(entries, socket.assigns.selected_entry, per_page)

        socket =
          socket
          |> assign(
            page: actual_page,
            page_count: page_count,
            total_count: total_count,
            load_error: nil
          )
          |> stream(:entries, entries, reset: true)

        if actual_page != page do
          push_patch(socket, to: vocab_path(search, sort, per_page, actual_page))
        else
          socket
        end

      {:error, _error} ->
        Logger.error("Failed to load vocabulary entries")

        socket
        |> assign(load_error: "We couldn't refresh your vocabulary. Please try again.")
        |> stream(:entries, [], reset: true)
    end
  end

  defp normalize_search(search) when is_binary(search), do: String.trim(search)
  defp normalize_search(_search), do: ""

  defp parse_per_page(value) do
    case Integer.parse(to_string(value || "")) do
      {per_page, ""} when per_page in @per_page_options -> per_page
      _ -> 10
    end
  end

  defp parse_page(value) do
    case Integer.parse(to_string(value || "")) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp note_form(note), do: to_form(%{"note" => note || ""}, as: :entry_note)

  defp hit_count_label("", count), do: if(count == 1, do: "word", else: "words")
  defp hit_count_label(_search, _count), do: "matches"

  defp vocab_path(search, sort, per_page, page) do
    ~p"/learn/vocab?#{%{q: search, sort: sort, per_page: per_page, page: page}}"
  end

  defp main_term(%Entry{lemma: lemma}) when is_binary(lemma) and lemma != "", do: lemma
  defp main_term(%Entry{lookup_text: lookup_text}), do: lookup_text

  defp collected_on(%Entry{inserted_at: inserted_at}) do
    inserted_at
    |> DateTime.to_date()
    |> Calendar.strftime("%b %d, %Y")
  end

  defp snapshot_senses(%Entry{dictionary_snapshot: snapshot}) when is_map(snapshot) do
    Map.get(snapshot, "senses") || Map.get(snapshot, :senses) || []
  end

  defp snapshot_senses(_entry), do: []

  defp list_meaning(entry) do
    entry
    |> snapshot_senses()
    |> Enum.find_value(fn sense ->
      case sense_text(sense) do
        text when is_binary(text) ->
          case String.trim(text) do
            "" -> nil
            text -> Enum.join(Enum.reject([sense_label(sense), text], &(&1 == "")), " ")
          end

        _ ->
          nil
      end
    end)
    |> case do
      nil -> "No saved definition"
      meaning -> meaning
    end
  end

  defp sense_text(sense) when is_map(sense) do
    Map.get(sense, "zh") || Map.get(sense, :zh)
  end

  defp sense_text(_sense), do: nil

  defp sense_label(sense) when is_map(sense) do
    [
      Map.get(sense, "pos") || Map.get(sense, :pos),
      Map.get(sense, "domain") || Map.get(sense, :domain)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  defp sense_label(_sense), do: ""
end
