class CreateRevisions < ActiveRecord::Migration[8.1]
  def change
    create_table :revisions do |t|
      t.references :unit, null: false, foreign_key: true
      t.references :language, foreign_key: true
      t.string :kind, null: false
      t.text :old_value
      t.text :new_value
      t.string :author

      t.timestamps
    end
  end
end
