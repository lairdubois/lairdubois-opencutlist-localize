# Languages writing compounds (Glossary : the expected term may be inside a longer word), formerly
# Glossary::COMPOUNDING, now toggled on the languages' management page
class AddCompoundingToLanguages < ActiveRecord::Migration[8.1]
  def up
    add_column :languages, :compounding, :boolean, default: false, null: false
    execute "UPDATE languages SET compounding = 1 WHERE code IN ('de', 'nl')"
  end

  def down
    remove_column :languages, :compounding
  end
end
