defmodule Eim.Dict.NormalizeTest do
  use ExUnit.Case, async: true

  alias Eim.Dict.{Normalize, Senses}

  test "normalizes whitespace, edge punctuation, and case" do
    assert {:ok, normalized} = Normalize.run("  (Idempotent,)  ")
    assert normalized.text == "Idempotent"
    assert normalized.lc == "idempotent"
    assert normalized.kind == :word
  end

  test "keeps punctuation inside technical terms" do
    assert {:ok, normalized} = Normalize.run("C++")
    assert normalized.text == "C++"
    assert Normalize.strip_word("long-time") == "longtime"
  end

  test "classifies phrases and sentences and rejects invalid input" do
    assert {:ok, %{kind: :phrase}} = Normalize.run("look up")
    assert {:ok, %{kind: :sentence}} = Normalize.run("This is a longer sentence.")
    assert {:error, :empty} = Normalize.run("   ")
    assert {:error, :too_long} = Normalize.run(String.duplicate("a", 501))
    assert {:error, :invalid_text} = Normalize.run(nil)
  end

  test "parses literal and actual newlines into senses" do
    assert [
             %{pos: "n", domain: nil, zh: "苹果"},
             %{pos: nil, domain: "计", zh: "缓存"}
           ] = Senses.parse("n. 苹果\\n[计] 缓存")

    assert [
             %{pos: "n", domain: nil, zh: "苹果"},
             %{pos: nil, domain: "计", zh: "缓存"}
           ] = Senses.parse("n. 苹果\n[计] 缓存")

    assert [%{pos: "vt", domain: nil, zh: "给"}] = Senses.parse("vt. 给")
    assert Senses.parse(nil) == []
  end
end
