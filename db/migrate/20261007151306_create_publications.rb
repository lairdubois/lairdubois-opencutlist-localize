class CreatePublications < ActiveRecord::Migration[8.1]
  def change
    create_table :publications do |t|
      t.string :branch
      t.string :commit_sha
      t.string :pr_url
      t.string :fr_hash
      t.references :user, foreign_key: true

      t.timestamps
    end
  end
end
