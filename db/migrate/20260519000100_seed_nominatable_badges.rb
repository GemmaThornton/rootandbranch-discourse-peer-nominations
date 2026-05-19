# frozen_string_literal: true

# Flags the 9 admin-created badges as nominatable on first install.
#
# The badges already exist on staging and production (IDs 116–124 at the time
# of writing, but we look up by name so an ID drift doesn't matter). This
# migration is idempotent — if a badge isn't found it logs and moves on
# without raising, so the migration still passes on a fresh dev DB.

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
        say "SKIP — badge not found by name: #{name.inspect} (this is OK on a fresh dev DB; check the spelling on staging/prod)"
        next
      end

      changed = false

      unless badge.multiple_grant
        badge.update_columns(multiple_grant: true)
        changed = true
      end

      current = badge.custom_fields["nominatable"]
      if current.to_s != "true"
        badge.custom_fields["nominatable"] = true
        badge.save_custom_fields(true)
        changed = true
      end

      say(changed ? "Flagged nominatable: #{name}" : "Already nominatable: #{name}")
    end
  end

  def down
    BADGE_NAMES.each do |name|
      badge = Badge.find_by(name: name)
      next unless badge
      badge.custom_fields["nominatable"] = false
      badge.save_custom_fields(true)
    end
  end
end
