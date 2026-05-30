# frozen_string_literal: true

# Per-grant visibility scope. Existing grants are all 'public' (no
# user-facing change). New scopes set by nominee at acceptance time:
#
#   public      — default, badge visible to everyone (Discourse default)
#   vs_only     — badge visible only to viewers in the VerifiedLeft
#                 group + admins/moderators + the nominee themselves
#   admin_only  — badge visible only to viewers in the Core group +
#                 admins/moderators + the nominee themselves
#
# The badge itself is granted normally by admin approval — this column
# narrows who sees it on profile pages, user cards, and the user badges
# index. The badge in the admin badge list is unaffected.
class AddVisibilityScopeToPeerNominationGrants < ActiveRecord::Migration[7.2]
  def up
    add_column :peer_nomination_grants, :visibility_scope, :string,
               null: false, default: "public"
    add_index :peer_nomination_grants, :visibility_scope
  end

  def down
    remove_index :peer_nomination_grants, :visibility_scope
    remove_column :peer_nomination_grants, :visibility_scope
  end
end
