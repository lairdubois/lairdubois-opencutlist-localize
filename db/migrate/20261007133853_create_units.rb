class CreateUnits < ActiveRecord::Migration[8.1]
  def change
    create_table :units do |t|
      t.string :key, null: false
      t.text :source_text, null: false
      t.string :source_hash
      t.text :note
      t.integer :position, null: false
      t.datetime :archived_at

      t.timestamps
    end
    add_index :units, :key, unique: true, where: "archived_at IS NULL"
  end
end
