# frozen_string_literal: true

# Ensures the 9 admin-created nominatable badges have `multiple_grant = true`
# so BadgeGranter creates a new UserBadge for each peer nomination instead
# of silently no-op'ing on the second nomination for the same person.
#
# Looks up by exact name, in step with PeerNominations::NOMINATABLE_BADGE_NAMES.
# Idempotent — skips quietly if a badge isn't found (e.g. on a fresh dev DB
# that doesn't have the 9 R&B badges) or is already multiple_grant.
#
# (Earlier versions of this migration tried to write a `nominatable` custom
# field on each Badge, but Discourse Badge has no `.custom_fields` accessor.
# The nominatable list is now a frozen constant in plugin.rb.)

class SeedNominatableBadges < ActiveRecord::Migration[7.0]
  BADGE_NAMES = [
    "Local Signpost",
    "Order Order!",
    "The IT Crowd",
    "Councillor",
    "Crowd Pleaser",
    "Doorstep Hero",
    "Got the T Shirt",
    "On It !",
    "Rule-book Guru",
  ].freeze

  def up
    BADGE_NAMES.each do |name|
      badge = Badge.find_by(name: name)
      if badge.nil?
        say "SKIP — badge not found by name: #{name.inspect} (OK on a fresh dev DB; verify spelling on staging/prod if unexpected)"
        next
      end

      if badge.multiple_grant
        say "Already multiple_grant: #{name}"
      else
        badge.update_columns(multiple_grant: true)
        say "Set multiple_grant=true: #{name}"
      end
    end
  end

  def down
    # No-op. Leaving multiple_grant=true is harmless if the plugin is removed
    # later; flipping it back to false could orphan existing UserBadge rows.
  end
end
