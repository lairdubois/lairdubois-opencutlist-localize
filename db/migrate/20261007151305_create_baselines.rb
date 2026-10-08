class CreateBaselines < ActiveRecord::Migration[8.1]
  def change
    create_table :baselines do |t|
      t.string :fr_hash
      t.json :entries
      t.string :source

      t.timestamps
    end
  end
end
