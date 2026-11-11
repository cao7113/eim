defmodule Eim.Repo.Migrations.AddEcdictAbbreviationIndex do
  use Ecto.Migration

  def change do
    create index(:lexemes, [:word_lc, :word],
             name: "lexemes_browse_abbreviation_index",
             where: "word ~ '([[:alpha:]][.][[:alnum:]]|[[:digit:]][.][[:alpha:]])'"
           )
  end
end
