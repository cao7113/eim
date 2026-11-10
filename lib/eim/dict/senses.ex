defmodule Eim.Dict.Senses do
  def parse(nil), do: []

  def parse(text) do
    text
    |> String.split(["\n", "\\n"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_line/1)
  end

  defp parse_line(line) do
    captures =
      Regex.named_captures(
        ~r/^(?:\[(?<domain>[^\]]+)\]\s*)?(?:(?<pos>[a-z]+)\.\s*)?(?<zh>.+)$/u,
        line
      )

    %{
      pos: nilify(captures["pos"]),
      domain: nilify(captures["domain"]),
      zh: captures["zh"]
    }
  end

  defp nilify(""), do: nil
  defp nilify(value), do: value
end
