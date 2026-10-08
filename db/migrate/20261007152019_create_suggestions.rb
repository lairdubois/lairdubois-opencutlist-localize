class CreateSuggestions < ActiveRecord::Migration[8.1]
  def change
    create_table :suggestions do |t|
      t.references :unit, null: false, foreign_key: true
      t.references :language, null: false, foreign_key: true
      t.text :text, null: false
      t.string :origin, null: false

      t.timestamps
    end
  end
end
