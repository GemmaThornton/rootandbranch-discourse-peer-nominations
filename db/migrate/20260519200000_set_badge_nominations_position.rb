# frozen_string_literal: true

# Pins the Badge Nominations category to Category.position = 13 so it
# sorts straight after Site Feedback (position 12) in the user-facing
# sidebar. Discourse renders the Categories sidebar by Category.position,
# not by per-user SidebarSectionLink.position — without this, the
# category is created at a default high position (109 on staging,
# similar on prod) and falls below the visible cut-off in the sidebar
# even for admins.
#
# Idempotent — if the category doesn't exist (fresh dev DB) or the
# position is already 13 (admin already nudged it via the panel), this
# is a no-op.
#
# Looks up by name; if the category is renamed in the admin panel, this
# migration silently skips. That's the right tradeoff — if an admin
# renames it, they probably also want to choose the new position.

class SetBadgeNominationsPosition < ActiveRecord::Migration[7.0]
  TARGET_POSITION = 13

  def up
    cat = Category.find_by(name: "Badge Nominations")
    if cat.nil?
      say "SKIP — no Badge Nominations category found (OK on fresh install)"
      return
    end

    if cat.position == TARGET_POSITION
      say "Already at position #{TARGET_POSITION}: Badge Nominations"
      return
    end

    cat.update_columns(position: TARGET_POSITION)
    say "Set Badge Nominations Category.position = #{TARGET_POSITION}"
  end

  def down
    # No-op. Leaving the position at 13 is harmless if the plugin is
    # removed; reverting to the previous arbitrary high position
    # would just hide the category from sidebars again.
  end
end
