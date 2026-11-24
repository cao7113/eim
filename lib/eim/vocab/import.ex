defmodule Eim.Vocab.Import do
  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias Eim.Dict.Lookup
  alias Eim.Vocab.Entry

  @max_entries 500

  def run(input, _opts, context) do
    # require Logger
    # IO.puts("Importing entries: #{inspect(input.arguments)}")
    # IO.puts(Jason.encode!(input.arguments))

    case import_entries(input.arguments.entries, context.actor) do
      {:ok, result} ->
        {:ok, result}

      {:error, :too_many_entries} ->
        {:error,
         Ash.Error.Query.InvalidArgument.exception(
           field: :entries,
           message: "must contain at most 500 entries"
         )}

      {:error, reason} ->
        {:error,
         Ash.Error.Query.InvalidArgument.exception(
           field: :entries,
           message: Atom.to_string(reason)
         )}
    end
  end

  def import_entries(entries, user) when is_list(entries) do
    with :ok <- validate_size(entries),
         {:ok, entries} <- normalize_entries(entries) do
      results = Enum.map(entries, &import_entry(&1, user))

      {:ok,
       %{
         total: length(results),
         matched: Enum.count(results, &(&1.status in [:created, :already_exists])),
         created: Enum.count(results, &(&1.status == :created)),
         updated: 0,
         skipped: Enum.count(results, &(&1.status == :not_found)),
         results: results
       }}
    end
  end

  defp validate_size(entries) when length(entries) <= @max_entries, do: :ok
  defp validate_size(_entries), do: {:error, :too_many_entries}

  defp normalize_entries(entries) do
    entries
    |> Enum.reduce_while({:ok, {MapSet.new(), []}}, fn entry, {:ok, {seen, normalized_entries}} ->
      case normalize_entry(entry) do
        {:ok, normalized} ->
          key = Entry.term_key_for(normalized.word)

          if MapSet.member?(seen, key) do
            {:cont, {:ok, {seen, normalized_entries}}}
          else
            {:cont, {:ok, {MapSet.put(seen, key), [normalized | normalized_entries]}}}
          end

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, {_seen, normalized_entries}} -> {:ok, Enum.reverse(normalized_entries)}
      error -> error
    end
  end

  defp normalize_entry(%{"word" => word} = entry) when is_binary(word) do
    word = String.trim(word)

    if word == "" or byte_size(word) > 500 do
      {:error, :invalid_word}
    else
      note = Map.get(entry, "note")

      if is_nil(note) or (is_binary(note) and byte_size(note) <= 2000),
        do: {:ok, %{word: word, note: note}},
        else: {:error, :invalid_note}
    end
  end

  defp normalize_entry(_entry), do: {:error, :invalid_entry}

  defp import_entry(%{word: word, note: note}, user) do
    case Lookup.run(word) do
      {:miss, _normalized} -> %{word: word, status: :not_found}
      {:ok, dictionary_entry} -> save_entry(word, note, dictionary_entry, user)
    end
  end

  defp save_entry(word, note, dictionary_entry, user) do
    term_key = Entry.term_key_for(dictionary_entry.lemma || word)

    case Entry
         |> Ash.Query.filter(term_key == ^term_key)
         |> Ash.read_one(domain: Eim.Vocab, actor: user) do
      {:ok, %Entry{id: id}} -> %{word: word, status: :already_exists, entry_id: id}
      {:ok, nil} -> create_entry(word, note, dictionary_entry, user)
      {:error, _reason} -> %{word: word, status: :error, reason: :read_failed}
    end
  end

  defp create_entry(word, note, dictionary_entry, user) do
    attrs = %{
      lookup_text: word,
      lemma: dictionary_entry.lemma,
      phonetic: dictionary_entry.phonetic,
      dictionary_snapshot: Map.from_struct(dictionary_entry),
      note: note
    }

    case Ash.create(Entry, attrs, action: :create, domain: Eim.Vocab, actor: user) do
      {:ok, entry} -> %{word: word, status: :created, entry_id: entry.id, lemma: entry.lemma}
      {:error, _reason} -> %{word: word, status: :error, reason: :create_failed}
    end
  end
end
