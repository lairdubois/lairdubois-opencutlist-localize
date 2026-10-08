class CreateTranslations < ActiveRecord::Migration[8.1]
  def change
    create_table :translations do |t|
      t.references :unit, null: false, foreign_key: true
      t.references :language, null: false, foreign_key: true
      t.text :text, null: false
      t.integer :status, null: false, default: 0
      t.string :source_hash

      t.timestamps
    end
    add_index :translations, [:unit_id, :language_id], unique: true
  end
end
