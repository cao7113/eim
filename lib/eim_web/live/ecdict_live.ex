defmodule EimWeb.EcdictLive do
  use EimWeb, :live_view

  require Ash.Query
  require Logger

  alias Eim.Dict.{EcdictBrowse, Senses}
  alias Eim.Vocab.Entry

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "ECDICT",
       query: "",
       category: "all",
       cursor: nil,
       form: to_form(%{"q" => ""}, as: :search),
       import: nil,
       error: nil,
       entry: nil,
       previous: nil,
       next: nil,
       saved_entry: nil,
       saved_entry_error: nil,
       shortcuts_open: false
     )
     |> stream(:entries, [])
     |> stream(:forms, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = Map.get(params, "q", "")
    cursor = Map.get(params, "cursor")
    category = Map.get(params, "category", "all")

    socket =
      assign(socket,
        query: query,
        category: category,
        cursor: cursor,
        form: to_form(%{"q" => if(is_binary(query), do: query, else: "")}, as: :search),
        error: nil,
        saved_entry: nil,
        saved_entry_error: nil
      )

    {:noreply, load_page(socket, params)}
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error] ->
      Logger.error("Failed to load ECDICT browser: #{Exception.message(error)}")

      {:noreply,
       socket
       |> assign(
         error: "The dictionary is temporarily unavailable. Please try again.",
         entry: nil
       )
       |> stream(:entries, [], reset: true)
       |> stream(:forms, [], reset: true)}
  end

  defp load_page(socket, params) do
    case EcdictBrowse.search(socket.assigns.query, socket.assigns.cursor, socket.assigns.category) do
      {:ok, result} ->
        socket
        |> assign(
          import: EcdictBrowse.latest_import(),
          previous: result.previous,
          next: result.next,
          entry: nil,
          page_title: "ECDICT"
        )
        |> stream(:entries, result.entries, reset: true)
        |> load_entry(params)

      {:error, :query_too_long} ->
        assign(socket, error: "Search must be 500 characters or fewer.")

      {:error, :invalid_query} ->
        assign(socket, error: "Invalid search. Please enter a word or phrase.")

      {:error, :invalid_cursor} ->
        assign(socket, error: "This page link is invalid. Start again from the dictionary.")

      {:error, :invalid_category} ->
        assign(socket, error: "This category is invalid. Start again from the dictionary.")
    end
  end

  defp load_entry(%{assigns: %{live_action: :index}} = socket, _params) do
    stream(socket, :forms, [], reset: true)
  end

  defp load_entry(%{assigns: %{live_action: :show}} = socket, %{"id" => id}) do
    case EcdictBrowse.entry(id) do
      {:ok, entry, forms} ->
        socket
        |> assign(entry: entry, page_title: "#{entry.word} · ECDICT")
        |> stream(:forms, forms, reset: true)
        |> load_saved_entry(entry)

      :not_found ->
        assign(socket, entry: nil, error: "This dictionary entry could not be found.")
    end
  end

  defp load_saved_entry(%{assigns: %{current_user: nil}} = socket, _entry), do: socket

  defp load_saved_entry(socket, entry) do
    term_key = Entry.term_key_for(entry.word)

    case Entry
         |> Ash.Query.filter(term_key == ^term_key)
         |> Ash.read_one(domain: Eim.Vocab, actor: socket.assigns.current_user) do
      {:ok, saved_entry} ->
        assign(socket, saved_entry: saved_entry, saved_entry_error: nil)

      {:error, error} ->
        Logger.error("Failed to load saved dictionary entry: #{inspect(error)}")
        assign(socket, saved_entry_error: "Could not check your saved words. Please refresh.")
    end
  end

  @impl true
  def handle_event("search", %{"search" => %{"q" => query}}, socket) do
    {:noreply,
     push_patch(socket, to: list_path(query, nil, socket.assigns.category), replace: true)}
  end

  def handle_event("category", %{"category" => category}, socket) do
    {:noreply, push_patch(socket, to: list_path(socket.assigns.query, nil, category))}
  end

  def handle_event("show-shortcuts", _, socket),
    do: {:noreply, assign(socket, shortcuts_open: true)}

  def handle_event("hide-shortcuts", _, socket),
    do: {:noreply, assign(socket, shortcuts_open: false)}

  def handle_event("save", _params, %{assigns: %{current_user: user, entry: entry}} = socket)
      when not is_nil(user) and not is_nil(entry) do
    snapshot = %{
      "text" => entry.word,
      "lemma" => entry.word,
      "phonetic" => entry.phonetic,
      "senses" => Senses.parse(entry.translation),
      "sources" => [
        %{
          "name" => "ecdict",
          "entry_id" => entry.id
        }
      ]
    }

    case Ash.create(
           Entry,
           %{
             lookup_text: entry.word,
             lemma: entry.word,
             phonetic: entry.phonetic,
             dictionary_snapshot: snapshot
           },
           action: :create,
           domain: Eim.Vocab,
           actor: user
         ) do
      {:ok, saved_entry} ->
        {:noreply, assign(socket, saved_entry: saved_entry, saved_entry_error: nil)}

      {:error, error} ->
        Logger.error("Failed to save dictionary entry: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, "Could not save this word. Please try again.")}
    end
  end

  def handle_event("save", _params, socket) do
    {:noreply, put_flash(socket, :error, "Sign in and open an entry to save it.")}
  end

  defp list_path(query, cursor, category) do
    params =
      %{}
      |> put_param("q", query)
      |> put_param("cursor", cursor)
      |> put_category(category)

    if params == %{}, do: "/dicts/ecdict", else: "/dicts/ecdict?" <> URI.encode_query(params)
  end

  defp detail_path(id, query, cursor, category) do
    params =
      %{}
      |> put_param("q", query)
      |> put_param("cursor", cursor)
      |> put_category(category)

    path = "/dicts/ecdict/#{id}"
    if params == %{}, do: path, else: path <> "?" <> URI.encode_query(params)
  end

  defp sign_in_path(id, query, cursor, category) do
    detail_path(id, query, cursor, category)
    |> String.split("?", parts: 2)
    |> case do
      [path] -> path <> "/sign-in"
      [path, params] -> path <> "/sign-in?" <> params
    end
  end

  defp put_param(params, _key, value) when value in [nil, ""], do: params
  defp put_param(params, key, value) when is_binary(value), do: Map.put(params, key, value)
  defp put_param(params, _key, _value), do: params
  defp put_category(params, "all"), do: params
  defp put_category(params, category), do: put_param(params, "category", category)

  defp summary(nil), do: "No translation available"

  defp summary(text) do
    text
    |> String.split(["\n", "\\n"], trim: true)
    |> List.first()
    |> case do
      nil -> "No translation available"
      line -> line
    end
  end
end
