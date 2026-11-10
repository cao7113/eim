defmodule Eim.Dict.ImporterTest do
  use Eim.DataCase, async: false

  alias Eim.Dict.{Importer, Lexeme, LexemeForm, Lookup}
  alias Eim.Repo

  @fixture Path.expand("../../support/fixtures/ecdict_sample.csv", __DIR__)

  test "imports rows idempotently and resolves inflected words" do
    assert %{row_count: 4, skipped_rows: 1} = Importer.run(@fixture, "test-version")
    assert %{row_count: 4, skipped_rows: 1} = Importer.run(@fixture, "test-version")

    assert Repo.aggregate(Lexeme, :count) == 4
    assert Repo.aggregate(LexemeForm, :count) == 5

    assert {:ok, entry} = Lookup.run("gave")
    assert entry.lemma == "give"
    assert entry.match == :exact

    assert entry.senses == [
             %{pos: "vt", domain: nil, zh: "给，授予"},
             %{pos: "vi", domain: nil, zh: "让步"}
           ]

    assert {:ok, entry} = Lookup.run("hyphenword")
    assert entry.lemma == "hyphen-word"
    assert entry.match == :fuzzy
  end
end
