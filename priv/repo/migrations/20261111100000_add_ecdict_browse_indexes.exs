defmodule Eim.Repo.Migrations.AddEcdictBrowseIndexes do
  use Ecto.Migration

  def up do
    execute "CREATE INDEX lexemes_word_lc_prefix_index ON lexemes (word_lc text_pattern_ops)"

    execute "CREATE INDEX lexeme_forms_form_lc_prefix_index ON lexeme_forms (form_lc text_pattern_ops)"

    execute """
    CREATE INDEX lexemes_browse_category_index ON lexemes
    ((CASE WHEN word ~ '[[:space:]]' THEN 'phrase'
           WHEN word LIKE '-%' OR word LIKE '%-' THEN 'affix'
           ELSE 'word' END), word_lc, word)
    """
  end

  def down do
    execute "DROP INDEX lexemes_browse_category_index"
    execute "DROP INDEX lexeme_forms_form_lc_prefix_index"
    execute "DROP INDEX lexemes_word_lc_prefix_index"
  end
end
