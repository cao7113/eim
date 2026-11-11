defmodule Eim.Repo.Migrations.UpdateEcdictBrowseCategories do
  use Ecto.Migration

  def up do
    execute "DROP INDEX lexemes_browse_category_index"

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
  end

  def down do
    execute "DROP INDEX lexemes_browse_category_index"

    execute """
    CREATE INDEX lexemes_browse_category_index ON lexemes
    ((CASE WHEN word ~ '[[:space:]]' THEN 'phrase'
           WHEN word LIKE '-%' OR word LIKE '%-' THEN 'affix'
           ELSE 'word' END), word_lc, word)
    """
  end
end
