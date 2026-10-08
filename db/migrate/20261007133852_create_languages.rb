class CreateLanguages < ActiveRecord::Migration[8.1]
  def change
    create_table :languages do |t|
      t.string :code
      t.string :name
      t.boolean :rtl, null: false, default: false
      t.integer :position

      t.timestamps
    end
    add_index :languages, :code, unique: true
  end
end
