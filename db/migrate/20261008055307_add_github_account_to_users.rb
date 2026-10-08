class AddGithubAccountToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :github_id, :bigint
    add_column :users, :github_login, :string
    add_column :users, :github_access_token, :text
    add_column :users, :github_token_expires_at, :datetime
    add_column :users, :github_refresh_token, :text
    add_column :users, :github_refresh_token_expires_at, :datetime
    add_index :users, :github_id, unique: true
  end
end
