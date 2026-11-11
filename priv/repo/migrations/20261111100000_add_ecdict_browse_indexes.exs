defmodule Eim.Repo.Migrations.AddEcdictBrowseIndexes do
  use Ecto.Migration

  def up do
    execute "CREATE INDEX lexemes_word_lc_prefix_index ON lexemes (word_lc text_pattern_ops)"

    execute "CREATE INDEX lexeme_forms_form_lc_prefix_index ON lexeme_forms (form_lc text_pattern_ops)"

    execute """
    CREATE INDEX lexemes_browse_category_index ON lexemes
    ((CASE WHEN word ~ '[[:space:]]' THEN 'phrase'
           WHEN word LIKE '-%' AND word LIKE '%-' THEN 'other'
           WHEN word LIKE '-%' THEN 'suffix'
           WHEN word LIKE '%-' THEN 'prefix'
           WHEN word LIKE '%-%' THEN 'compound'
           WHEN word ~ '^[[:alpha:]]+$' THEN 'word'
           ELSE 'other' END), word_lc, word)
    """

    create index(:lexemes, [:word_lc, :word],
             name: "lexemes_browse_abbreviation_index",
             where: "word ~ '([[:alpha:]][.][[:alnum:]]|[[:digit:]][.][[:alpha:]])'"
           )
  end

  def down do
    drop index(:lexemes, [:word_lc, :word], name: "lexemes_browse_abbreviation_index")
    execute "DROP INDEX lexemes_browse_category_index"
    execute "DROP INDEX lexeme_forms_form_lc_prefix_index"
    execute "DROP INDEX lexemes_word_lc_prefix_index"
  end
end
