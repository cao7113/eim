defmodule Eim.Dict.Lookup do
  require Ash.Query

  alias Eim.Dict.{Entry, Lexeme, LexemeForm, Normalize, Senses}

  def run(text) do
    with {:ok, normalized} <- Normalize.run(text) do
      if normalized.kind == :sentence do
        {:miss, normalized}
      else
        resolve(normalized)
      end
    end
  end

  defp resolve(normalized) do
    cond do
      lexeme = exact(normalized.lc) ->
        {:ok, build(normalized, lexeme, :exact)}

      lexeme = via_form(normalized.lc) ->
        {:ok, build(normalized, lexeme, :form)}

      lexeme = fuzzy(normalized.lc) ->
        {:ok, build(normalized, lexeme, :fuzzy)}

      true ->
        {:miss, normalized}
    end
  end

  defp exact(word_lc) do
    Lexeme
    |> Ash.Query.filter(word_lc == ^word_lc)
    |> Ash.Query.limit(10)
    |> Ash.read!(domain: Eim.Dict)
    |> best_exact(word_lc)
  end

  defp best_exact(lexemes, word_lc) do
    Enum.find(lexemes, &(&1.word == word_lc)) || best(lexemes)
  end

  defp via_form(form_lc) do
    LexemeForm
    |> Ash.Query.filter(form_lc == ^form_lc)
    |> Ash.Query.load(:lexeme)
    |> Ash.read!(domain: Eim.Dict)
    |> Enum.map(& &1.lexeme)
    |> best()
  end

  defp fuzzy(word_lc) do
    sw = Normalize.strip_word(word_lc)

    if sw == "" do
      nil
    else
      Lexeme
      |> Ash.Query.filter(sw == ^sw)
      |> Ash.Query.limit(10)
      |> Ash.read!(domain: Eim.Dict)
      |> best()
    end
  end

  defp best([]), do: nil
  defp best(lexemes), do: Enum.min_by(lexemes, &rank/1)

  defp rank(%{frq_rank: rank}) when is_integer(rank) and rank > 0, do: rank
  defp rank(_), do: 1_000_000_000

  defp build(normalized, lexeme, match) do
    primary = (lexeme.lemma && exact(String.downcase(lexeme.lemma))) || lexeme

    %Entry{
      text: normalized.text,
      kind: normalized.kind,
      match: match,
      lemma: primary.word,
      phonetic: primary.phonetic,
      collins: primary.collins,
      frq_rank: primary.frq_rank,
      senses: Senses.parse(primary.translation),
      tags: primary.tags || [],
      sources: [%{name: primary.source, version: primary.source_version}]
    }
  end
end
