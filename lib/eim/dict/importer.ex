defmodule Eim.Dict.Importer do
  import Ecto.Query

  alias Eim.Dict.{Import, Normalize}
  alias Eim.Repo
  alias NimbleCSV.RFC4180, as: CSV

  require Logger

  @header ~w(word phonetic definition translation pos collins oxford tag bnc frq exchange)
  @form_types %{
    "p" => "past",
    "d" => "past_participle",
    "i" => "present_participle",
    "3" => "third_person",
    "r" => "comparative",
    "t" => "superlative",
    "s" => "plural"
  }
  @batch_size 2_000

  def run(path) do
    started_at = System.monotonic_time(:millisecond)
    path = local_path!(path)
    source_sha256 = source_sha256(path)
    counts = import_file(path, path)
    duration_ms = System.monotonic_time(:millisecond) - started_at

    notes =
      if counts.skipped_rows == 0 do
        nil
      else
        "Skipped #{counts.skipped_rows} blank or malformed CSV rows"
      end

    Import
    |> Ash.Changeset.for_create(:record, %{
      source_path: path,
      source_sha256: source_sha256,
      row_count: counts.row_count,
      duration_ms: duration_ms,
      notes: notes
    })
    |> Ash.create!(domain: Eim.Dict)

    counts
  end

  defp local_path!(path) do
    case URI.parse(path) do
      %URI{scheme: nil} -> Path.expand(path)
      _ -> raise ArgumentError, "ECDICT import requires a local file path: #{path}"
    end
  end

  defp source_sha256(path) do
    path
    |> File.stream!(64 * 1024, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp import_file(path, source) do
    validate_header!(path)

    path
    |> File.stream!()
    |> CSV.parse_stream()
    |> Stream.chunk_every(@batch_size)
    |> Enum.reduce(%{row_count: 0, skipped_rows: 0}, fn rows, counts ->
      {pairs, skipped_rows} =
        Enum.reduce(rows, {[], 0}, fn row, {pairs, skipped} ->
          case to_row(row, source) do
            nil -> {pairs, skipped + 1}
            pair -> {[pair | pairs], skipped}
          end
        end)

      pairs = Enum.reverse(pairs)
      imported_rows = insert_chunk(pairs)
      total_imported = counts.row_count + imported_rows
      Logger.info("imported: #{imported_rows}, total imported: #{total_imported}")

      %{
        row_count: total_imported,
        skipped_rows: counts.skipped_rows + skipped_rows
      }
    end)
  end

  def parse_exchange(nil), do: {nil, []}
  def parse_exchange(""), do: {nil, []}

  def parse_exchange(exchange) do
    items =
      for item <- String.split(exchange, "/", trim: true),
          [key, value] <- [String.split(item, ":", parts: 2)],
          value != "",
          do: {key, value}

    lemma = Enum.find_value(items, fn {key, value} -> if key == "0", do: value end)

    forms =
      items
      |> Enum.flat_map(fn {key, value} ->
        case Map.fetch(@form_types, key) do
          {:ok, type} -> [{type, value}]
          :error -> []
        end
      end)
      |> Enum.uniq()

    {lemma, forms}
  end

  defp validate_header!(path) do
    case path
         |> File.stream!()
         |> CSV.parse_stream(skip_headers: false)
         |> Enum.take(1) do
      [header] ->
        if Enum.take(header, length(@header)) != @header do
          raise "unexpected ECDICT CSV header: #{inspect(header)}"
        end

      [] ->
        raise "ECDICT CSV is empty"
    end
  end

  defp to_row(
         [
           word,
           phonetic,
           definition,
           translation,
           pos,
           collins,
           oxford,
           tag,
           bnc,
           frq,
           exchange
           | _
         ],
         source
       ) do
    word = String.trim(word)

    if word == "" do
      nil
    else
      {lemma, forms} = parse_exchange(blank(exchange))
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      row = %{
        word: word,
        word_lc: String.downcase(word),
        sw: Normalize.strip_word(word),
        phonetic: blank(phonetic),
        translation: blank(translation),
        definition: blank(definition),
        pos: blank(pos),
        tags: String.split(tag, " ", trim: true),
        collins: to_positive_integer(collins),
        oxford: oxford == "1",
        bnc_rank: to_positive_integer(bnc),
        frq_rank: to_positive_integer(frq),
        exchange: blank(exchange),
        lemma: lemma,
        source: source,
        inserted_at: now,
        updated_at: now
      }

      {row, forms}
    end
  end

  defp to_row(_, _), do: nil

  defp insert_chunk([]), do: 0

  defp insert_chunk(pairs) do
    pairs =
      pairs
      |> Enum.reverse()
      |> Enum.uniq_by(fn {row, _forms} -> row.word end)
      |> Enum.reverse()

    rows = Enum.map(pairs, fn {row, _forms} -> row end)
    replace = Map.keys(hd(rows)) -- [:word, :inserted_at]

    Repo.transaction(fn ->
      {_, returned} =
        Repo.insert_all("lexemes", rows,
          on_conflict: {:replace, replace},
          conflict_target: [:word],
          returning: [:id, :word]
        )

      ids = Map.new(returned, &{&1.word, &1.id})
      lexeme_ids = Map.values(ids)
      Repo.delete_all(from(form in "lexeme_forms", where: form.lexeme_id in ^lexeme_ids))

      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      forms =
        for {row, row_forms} <- pairs,
            {type, form} <- row_forms,
            id = ids[row.word] do
          %{
            lexeme_id: id,
            form: form,
            form_lc: String.downcase(form),
            form_type: type,
            inserted_at: now,
            updated_at: now
          }
        end

      if forms != [] do
        Repo.insert_all("lexeme_forms", forms, on_conflict: :nothing)
      end
    end)
    |> case do
      {:ok, _} -> length(pairs)
      {:error, reason} -> raise "failed to import ECDICT chunk: #{inspect(reason)}"
    end
  end

  defp blank(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp to_positive_integer(value) do
    case Integer.parse(String.trim(value)) do
      {number, ""} when number > 0 -> number
      _ -> nil
    end
  end
end
