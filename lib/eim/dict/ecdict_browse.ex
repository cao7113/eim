defmodule Eim.Dict.EcdictBrowse do
  @moduledoc """
  Read-only ECDICT browsing, independent of the plugin lookup contract.
  """
  import Ecto.Query

  alias Eim.Dict.{Import, Lexeme, LexemeForm}
  alias Eim.Repo

  @page_size 10
  @max_cursor_length 2048

  def search(query, cursor, category \\ "all") do
    with {:ok, term} <- normalize_query(query),
         {:ok, position} <- decode_cursor(cursor),
         :ok <- validate_category(category) do
      direction = if position && position.direction == "before", do: :desc, else: :asc
      base = from l in Lexeme, where: l.source == "ecdict"
      base = base |> apply_category(category) |> apply_position(position)

      results =
        if term == "" do
          page(base, direction)
        else
          pattern = escape_like(term) <> "%"

          words =
            base
            |> where([l], like(l.word_lc, ^pattern))
            |> candidate_ids(direction)

          # Keep the indexed form-prefix lookup ahead of the lexeme join.
          matching_forms =
            from f in LexemeForm,
              where: like(f.form_lc, ^pattern),
              distinct: true,
              select: %{lexeme_id: f.lexeme_id},
              offset: 0

          form_entries =
            base
            |> join(:inner, [l], f in subquery(matching_forms), on: f.lexeme_id == l.id)
            |> candidate_ids(direction)

          matches = union_all(words, ^form_entries)

          base
          |> where([l], l.id in subquery(matches))
          |> page(direction)
        end

      extra? = length(results) > @page_size
      entries = Enum.take(results, @page_size)
      entries = if direction == :desc, do: Enum.reverse(entries), else: entries

      {:ok,
       %{
         entries: entries,
         previous: cursor_for(List.first(entries), "before", previous?(position, extra?)),
         next: cursor_for(List.last(entries), "after", next?(position, extra?))
       }}
    end
  end

  def latest_import do
    Repo.one(
      from i in Import,
        where: i.source == "ecdict",
        order_by: [desc: i.inserted_at, desc: i.id],
        limit: 1
    )
  end

  def entry(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        case Repo.one(from l in Lexeme, where: l.id == ^uuid and l.source == "ecdict") do
          nil ->
            :not_found

          lexeme ->
            forms =
              Repo.all(
                from f in LexemeForm,
                  where: f.lexeme_id == ^lexeme.id,
                  order_by: [asc: f.form, asc: f.form_type]
              )

            {:ok, lexeme, forms}
        end

      :error ->
        :not_found
    end
  end

  defp normalize_query(query) when is_binary(query) do
    query = query |> String.trim() |> String.replace(~r/\s+/u, " ") |> String.downcase()
    if String.length(query) <= 500, do: {:ok, query}, else: {:error, :query_too_long}
  end

  defp normalize_query(_), do: {:error, :invalid_query}

  defp validate_category(category)
       when category in [
              "all",
              "word",
              "phrase",
              "affix",
              "prefix",
              "suffix",
              "compound",
              "abbreviation",
              "other"
            ],
       do: :ok

  defp validate_category(_), do: {:error, :invalid_category}

  defp escape_like(term) do
    term
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp apply_category(query, "all"), do: query

  defp apply_category(query, "abbreviation") do
    where(
      query,
      [l],
      fragment(
        "? ~ '([[:alpha:]][.][[:alnum:]]|[[:digit:]][.][[:alpha:]])'",
        l.word
      )
    )
  end

  defp apply_category(query, "affix") do
    where(
      query,
      [l],
      fragment(
        "CASE WHEN ? ~ '[[:space:]]' THEN 'phrase' WHEN ? LIKE '-%' AND ? LIKE '%-' THEN 'other' WHEN ? LIKE '-%' THEN 'suffix' WHEN ? LIKE '%-' THEN 'prefix' WHEN ? LIKE '%-%' THEN 'compound' WHEN ? ~ '^[[:alpha:]]+$' THEN 'word' ELSE 'other' END IN ('prefix', 'suffix')",
        l.word,
        l.word,
        l.word,
        l.word,
        l.word,
        l.word,
        l.word
      )
    )
  end

  defp apply_category(query, category) do
    where(
      query,
      [l],
      fragment(
        "CASE WHEN ? ~ '[[:space:]]' THEN 'phrase' WHEN ? LIKE '-%' AND ? LIKE '%-' THEN 'other' WHEN ? LIKE '-%' THEN 'suffix' WHEN ? LIKE '%-' THEN 'prefix' WHEN ? LIKE '%-%' THEN 'compound' WHEN ? ~ '^[[:alpha:]]+$' THEN 'word' ELSE 'other' END = ?",
        l.word,
        l.word,
        l.word,
        l.word,
        l.word,
        l.word,
        l.word,
        ^category
      )
    )
  end

  defp candidate_ids(query, direction) do
    query
    |> order_by([l], [{^direction, l.word_lc}, {^direction, l.word}])
    |> limit(^(@page_size + 1))
    |> select([l], %{id: l.id, word_lc: l.word_lc, word: l.word})
    |> subquery()
    |> then(&from(candidate in &1, select: candidate.id))
  end

  defp page(query, direction) do
    query
    |> order_by([l], [{^direction, l.word_lc}, {^direction, l.word}])
    |> limit(^(@page_size + 1))
    |> Repo.all()
  end

  defp apply_position(query, nil), do: query

  defp apply_position(query, %{direction: "after", lc: lc, word: word}) do
    where(query, [l], fragment("(?, ?) > (?, ?)", l.word_lc, l.word, ^lc, ^word))
  end

  defp apply_position(query, %{direction: "before", lc: lc, word: word}) do
    where(query, [l], fragment("(?, ?) < (?, ?)", l.word_lc, l.word, ^lc, ^word))
  end

  defp decode_cursor(nil), do: {:ok, nil}
  defp decode_cursor(""), do: {:ok, nil}

  defp decode_cursor(cursor) when is_binary(cursor) and byte_size(cursor) <= @max_cursor_length do
    with {:ok, json} <- Base.url_decode64(cursor, padding: false),
         {:ok, %{"direction" => direction, "lc" => lc, "word" => word}} <- Jason.decode(json),
         true <- direction in ["after", "before"],
         true <- is_binary(lc) and is_binary(word),
         true <- byte_size(lc) <= 500 and byte_size(word) <= 500 do
      {:ok, %{direction: direction, lc: lc, word: word}}
    else
      _ -> {:error, :invalid_cursor}
    end
  end

  defp decode_cursor(_), do: {:error, :invalid_cursor}

  defp cursor_for(nil, _, _), do: nil
  defp cursor_for(_, _, false), do: nil

  defp cursor_for(entry, direction, true) do
    %{direction: direction, lc: entry.word_lc, word: entry.word}
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  defp previous?(nil, _), do: false
  defp previous?(%{direction: "after"}, _), do: true
  defp previous?(%{direction: "before"}, extra?), do: extra?

  defp next?(nil, extra?), do: extra?
  defp next?(%{direction: "after"}, extra?), do: extra?
  defp next?(%{direction: "before"}, _), do: true
end
