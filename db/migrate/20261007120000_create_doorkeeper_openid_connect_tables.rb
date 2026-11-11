# frozen_string_literal: true

class CreateDoorkeeperOpenidConnectTables < ActiveRecord::Migration[8.1]
  def up
    unless table_exists?(:oauth_openid_requests)
      create_table :oauth_openid_requests do |t|
        t.references :access_grant, null: false, index: true
        t.string :nonce, null: false
      end
    end

    unless foreign_key_exists?(:oauth_openid_requests, :oauth_access_grants)
      add_foreign_key(
        :oauth_openid_requests,
        :oauth_access_grants,
        column: :access_grant_id,
        on_delete: :cascade
      )
    end

    unless column_exists?(:oauth_applications, :post_logout_redirect_uris)
      add_column :oauth_applications, :post_logout_redirect_uris, :text
    end
  end

  def down
    if column_exists?(:oauth_applications, :post_logout_redirect_uris)
      remove_column :oauth_applications, :post_logout_redirect_uris
    end

    if foreign_key_exists?(:oauth_openid_requests, :oauth_access_grants)
      remove_foreign_key :oauth_openid_requests, :oauth_access_grants
    end

    if table_exists?(:oauth_openid_requests)
      drop_table :oauth_openid_requests
    end
  end
end
