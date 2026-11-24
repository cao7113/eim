defmodule Eim.Vocab.Changes.SetTermKey do
  use Ash.Resource.Change

  alias Eim.Vocab.Entry

  @impl true
  def change(changeset, _opts, _context) do
    lookup_text = Ash.Changeset.get_attribute(changeset, :lookup_text)
    lemma = Ash.Changeset.get_attribute(changeset, :lemma)
    term = if is_binary(lemma) and String.trim(lemma) != "", do: lemma, else: lookup_text

    normalized_term = Entry.term_key_for(term)

    if normalized_term == "" do
      Ash.Changeset.add_error(changeset,
        field: :lookup_text,
        message: "must not be blank"
      )
    else
      Ash.Changeset.change_attribute(changeset, :term_key, normalized_term)
    end
  end
end
