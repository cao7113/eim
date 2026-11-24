defmodule Eim.Vocab.EntryTest do
  use Eim.DataCase, async: true

  alias Eim.Vocab.Entry

  describe "term_key_for/1" do
    test "normalizes a term" do
      assert Entry.term_key_for("  Ｈｅｌｌｏ  ") == "hello"
    end

    test "returns an empty key for nil" do
      assert Entry.term_key_for(nil) == ""
    end
  end
end
