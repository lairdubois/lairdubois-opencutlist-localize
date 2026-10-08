class AddUserToRevisions < ActiveRecord::Migration[8.1]
  def change
    add_reference :revisions, :user, foreign_key: true
  end
end
