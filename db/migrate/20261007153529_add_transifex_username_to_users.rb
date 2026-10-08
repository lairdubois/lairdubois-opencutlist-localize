class AddTransifexUsernameToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :transifex_username, :string
    add_index :users, :transifex_username, unique: true
  end
end
