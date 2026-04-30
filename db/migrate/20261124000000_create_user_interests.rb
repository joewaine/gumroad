# frozen_string_literal: true

class CreateUserInterests < ActiveRecord::Migration[7.1]
  def change
    create_table :user_interests do |t|
      t.bigint :user_id, null: false
      t.bigint :taxonomy_id, null: false
      t.string :source_text

      t.timestamps

      t.index [:user_id, :taxonomy_id], unique: true
      t.index :taxonomy_id
    end
  end
end
