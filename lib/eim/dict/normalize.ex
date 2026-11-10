defmodule Eim.Dict.Normalize do
  @max_len 500

  def run(text) when is_binary(text) do
    text = text |> String.replace(~r/\s+/u, " ") |> String.trim()
    kind = kind(text)
    text = if kind == :sentence, do: text, else: trim_edge(text)

    cond do
      text == "" ->
        {:error, :empty}

      String.length(text) > @max_len ->
        {:error, :too_long}

      true ->
        {:ok,
         %{
           text: text,
           lc: String.downcase(text),
           kind: kind,
           hash: :crypto.hash(:sha256, String.downcase(text)) |> Base.encode16(case: :lower)
         }}
    end
  end

  def run(_), do: {:error, :invalid_text}

  def strip_word(text) do
    text
    |> String.replace(~r/[^\p{L}\p{N}]/u, "")
    |> String.downcase()
  end

  defp trim_edge(text) do
    String.replace(text, ~r/^[\s"'(\[]+|[\s.,;:!?"')\]]+$/u, "")
  end

  defp kind(text) do
    case length(String.split(text)) do
      1 -> :word
      words when words <= 4 -> :phrase
      _ -> :sentence
    end
  end
end
