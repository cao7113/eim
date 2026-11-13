defmodule Eim.Dict.EcdictBrowseTest do
  use Eim.DataCase, async: false

  alias Eim.Dict.{EcdictBrowse, Importer}
  alias Eim.Repo

  @fixture Path.expand("../../support/fixtures/ecdict_sample.csv", __DIR__)

  test "exact and form matches are combined without duplicate source entries" do
    Importer.run(@fixture)

    assert {:ok, result} = EcdictBrowse.search(" GaVe ", nil)
    assert Enum.map(result.entries, & &1.word) == ["gave", "give"]
    assert result.previous == nil
    assert result.next == nil
  end

  test "paginates in both directions with stable cursors" do
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

    Repo.insert_all("lexemes", rows)
    assert {:ok, first} = EcdictBrowse.search("", nil)
    assert length(first.entries) == 10
    assert first.previous == nil
    assert first.next

    assert {:ok, second} = EcdictBrowse.search("", first.next)
    assert length(second.entries) == 10
    assert second.previous
    assert second.next
    assert {:ok, third} = EcdictBrowse.search("", second.next)
    assert length(third.entries) == 5
    assert third.next == nil

    assert {:ok, back} = EcdictBrowse.search("", second.previous)
    assert Enum.map(back.entries, & &1.id) == Enum.map(first.entries, & &1.id)
    assert back.previous == nil
    assert back.next
  end

  test "cursor retains entries with the same lowercase key" do
    now = DateTime.utc_now()

    rows =
      for index <- 1..9 do
        word = "a#{String.pad_leading(Integer.to_string(index), 2, "0")}"

        %{
          word: word,
          word_lc: word,
          sw: word,
          source: "ecdict",
          inserted_at: now,
          updated_at: now
        }
      end

    rows =
      rows ++
        for word <- ["Word", "word"] do
          %{
            word: word,
            word_lc: "word",
            sw: "word",
            source: "ecdict",
            inserted_at: now,
            updated_at: now
          }
        end

    Repo.insert_all("lexemes", rows)
    assert {:ok, first} = EcdictBrowse.search("", nil)
    assert length(first.entries) == 10
    assert {:ok, second} = EcdictBrowse.search("", first.next)
    assert length(second.entries) == 1

    assert MapSet.new(Enum.map(first.entries ++ second.entries, & &1.word)) ==
             MapSet.new(Enum.map(rows, & &1.word))
  end

  test "matches literal prefixes and form prefixes without duplicate entries" do
    Importer.run(@fixture)
    now = DateTime.utc_now()

    rows =
      for word <- ["gift", "give up", "-give", "give%", "give_"] do
        %{
          word: word,
          word_lc: word,
          sw: word,
          source: "ecdict",
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all("lexemes", rows)
    assert {:ok, result} = EcdictBrowse.search("gi", nil)

    assert MapSet.new(Enum.map(result.entries, & &1.word)) ==
             MapSet.new(["gift", "give", "give up", "give%", "give_"])

    assert {:ok, forms} = EcdictBrowse.search("givin", nil)
    assert Enum.map(forms.entries, & &1.word) == ["give"]
    assert {:ok, percent} = EcdictBrowse.search("give%", nil)
    assert Enum.map(percent.entries, & &1.word) == ["give%"]
    assert {:ok, underscore} = EcdictBrowse.search("give_", nil)
    assert Enum.map(underscore.entries, & &1.word) == ["give_"]
  end

  test "categories use spelling and combine with prefix filtering" do
    now = DateTime.utc_now()

    rows =
      for word <- [
            "apple",
            "café",
            "apple pie",
            "apple-pie",
            "apple-",
            "-apple",
            "apple -pie",
            "can't",
            "abc123",
            "U.S.",
            "two--parts",
            "-both-"
          ] do
        %{
          word: word,
          word_lc: word,
          sw: word,
          source: "ecdict",
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all("lexemes", rows)
    assert {:ok, single} = EcdictBrowse.search("apple", nil, "word")
    assert Enum.map(single.entries, & &1.word) == ["apple"]
    assert {:ok, phrases} = EcdictBrowse.search("apple", nil, "phrase")
    assert Enum.map(phrases.entries, & &1.word) == ["apple -pie", "apple pie"]
    assert {:ok, affixes} = EcdictBrowse.search("", nil, "affix")
    assert Enum.map(affixes.entries, & &1.word) == ["-apple", "apple-"]
    assert {:ok, prefixes} = EcdictBrowse.search("", nil, "prefix")
    assert Enum.map(prefixes.entries, & &1.word) == ["apple-"]
    assert {:ok, suffixes} = EcdictBrowse.search("", nil, "suffix")
    assert Enum.map(suffixes.entries, & &1.word) == ["-apple"]
    assert {:ok, compounds} = EcdictBrowse.search("", nil, "compound")

    assert MapSet.new(Enum.map(compounds.entries, & &1.word)) ==
             MapSet.new(["apple-pie", "two--parts"])

    assert {:ok, other} = EcdictBrowse.search("", nil, "other")

    assert MapSet.new(Enum.map(other.entries, & &1.word)) ==
             MapSet.new(["can't", "abc123", "U.S.", "-both-"])

    assert {:ok, accented} = EcdictBrowse.search("café", nil, "word")
    assert Enum.map(accented.entries, & &1.word) == ["café"]
    assert {:error, :invalid_category} = EcdictBrowse.search("", nil, "root")
  end

  test "dotted abbreviations require alphanumeric neighbors and at least one letter" do
    now = DateTime.utc_now()

    words = [
      "A.B.G.",
      "U.S.",
      "A.1",
      "1.A",
      "A.B. test",
      "A.B-word",
      "6.2",
      ".45",
      "a...",
      "a.",
      ".b"
    ]

    rows =
      for word <- words do
        %{
          word: word,
          word_lc: String.downcase(word),
          sw: word,
          source: "ecdict",
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all("lexemes", rows)
    assert {:ok, result} = EcdictBrowse.search("", nil, "abbreviation")

    assert MapSet.new(Enum.map(result.entries, & &1.word)) ==
             MapSet.new(["A.B.G.", "U.S.", "A.1", "1.A", "A.B. test", "A.B-word"])

    assert {:ok, prefix} = EcdictBrowse.search("a.b", nil, "abbreviation")

    assert MapSet.new(Enum.map(prefix.entries, & &1.word)) ==
             MapSet.new(["A.B.G.", "A.B. test", "A.B-word"])

    assert {:ok, phrases} = EcdictBrowse.search("a.b", nil, "phrase")
    assert Enum.map(phrases.entries, & &1.word) == ["A.B. test"]
    assert {:ok, compounds} = EcdictBrowse.search("a.b", nil, "compound")
    assert Enum.map(compounds.entries, & &1.word) == ["A.B-word"]
  end

  test "dotted abbreviation pagination keeps all matches" do
    now = DateTime.utc_now()

    rows =
      for index <- 1..25 do
        word = "a.#{String.pad_leading(Integer.to_string(index), 2, "0")}"

        %{
          word: word,
          word_lc: word,
          sw: word,
          source: "ecdict",
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all("lexemes", rows)
    assert {:ok, first} = EcdictBrowse.search("a.", nil, "abbreviation")
    assert length(first.entries) == 10
    assert {:ok, second} = EcdictBrowse.search("a.", first.next, "abbreviation")
    assert {:ok, third} = EcdictBrowse.search("a.", second.next, "abbreviation")
    assert length(third.entries) == 5
    assert third.next == nil
    assert {:ok, back} = EcdictBrowse.search("a.", third.previous, "abbreviation")
    assert Enum.map(back.entries, & &1.id) == Enum.map(second.entries, & &1.id)
    assert length(Enum.uniq_by(first.entries ++ second.entries ++ third.entries, & &1.id)) == 25
  end

  test "prefix search paginates across more than one page" do
    now = DateTime.utc_now()

    rows =
      for index <- 1..25 do
        word = "prefix#{String.pad_leading(Integer.to_string(index), 2, "0")}"

        %{
          word: word,
          word_lc: word,
          sw: word,
          source: "ecdict",
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all("lexemes", rows)
    assert {:ok, first} = EcdictBrowse.search("prefix", nil, "other")
    assert length(first.entries) == 10
    assert {:ok, second} = EcdictBrowse.search("prefix", first.next, "other")
    assert length(second.entries) == 10
    assert {:ok, third} = EcdictBrowse.search("prefix", second.next, "other")
    assert length(third.entries) == 5
    assert {:ok, back} = EcdictBrowse.search("prefix", second.previous, "other")
    assert Enum.map(back.entries, & &1.id) == Enum.map(first.entries, & &1.id)
    assert length(Enum.uniq_by(first.entries ++ second.entries ++ third.entries, & &1.id)) == 25
  end

  test "word and form prefix candidates deduplicate across pages" do
    now = DateTime.utc_now()

    rows =
      for index <- 1..25 do
        word = if index <= 12, do: "match#{index}", else: "other#{index}"

        %{
          word: word,
          word_lc: word,
          sw: word,
          source: "ecdict",
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all("lexemes", rows)
    entries = Repo.all(Eim.Dict.Lexeme)

    forms =
      for entry <- entries, form_type <- ["past", "plural"] do
        %{
          lexeme_id: Ecto.UUID.dump!(entry.id),
          form: "matching",
          form_lc: "matching",
          form_type: form_type,
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all("lexeme_forms", forms)
    assert {:ok, first} = EcdictBrowse.search("match", nil)
    assert {:ok, second} = EcdictBrowse.search("match", first.next)
    assert {:ok, third} = EcdictBrowse.search("match", second.next)
    assert third.next == nil
    assert length(Enum.uniq_by(first.entries ++ second.entries ++ third.entries, & &1.id)) == 25
    assert {:ok, back} = EcdictBrowse.search("match", third.previous)
    assert Enum.map(back.entries, & &1.id) == Enum.map(second.entries, & &1.id)
  end
end
