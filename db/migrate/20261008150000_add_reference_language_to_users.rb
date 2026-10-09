class AddReferenceLanguageToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :reference_language, :string, null: false, default: "fr"
  end
end
