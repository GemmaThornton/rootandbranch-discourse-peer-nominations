# frozen_string_literal: true

# name: peer-nominations
# about: Lets members nominate other members for badges. Nominations become topics in an admin-only category for review.
# version: 0.1.0
# authors: Root & Branch Organising
# url: https://github.com/GemmaThornton/rootandbranch-discourse-peer-nominations
# required_version: 3.0.0

enabled_site_setting :peer_nominations_enabled

register_asset "stylesheets/peer-nominations.scss"

module ::PeerNominations
  PLUGIN_NAME = "peer-nominations"

  # Custom field name on Badge — set to "true" (string) to make a badge nominatable.
  NOMINATABLE_FIELD = "nominatable"

  # Topic custom field names — used to store the nominator/nominee/badge
  # association on the nomination topic itself, so the topic IS the
  # nomination (no separate nominations table required).
  TOPIC_NOMINATOR_ID = "peer_nom_nominator_id"
  TOPIC_NOMINEE_ID   = "peer_nom_nominee_id"
  TOPIC_BADGE_ID     = "peer_nom_badge_id"
  TOPIC_STATE        = "peer_nom_state" # "under-review" | "approved" | "declined"
  TOPIC_DECLINE_REASON = "peer_nom_decline_reason"

  TAG_UNDER_REVIEW = "under-review"
  TAG_APPROVED     = "approved"
  TAG_DECLINED     = "declined"
end

require_relative "lib/peer_nominations/engine"

after_initialize do
  load File.expand_path("../app/models/peer_nomination_grant.rb", __FILE__)
  load File.expand_path("../app/controllers/peer_nominations/nominations_controller.rb", __FILE__)
  load File.expand_path("../app/serializers/peer_nominations/nominatable_badge_serializer.rb", __FILE__)
  load File.expand_path("../lib/peer_nominations/nomination_creator.rb", __FILE__)
  load File.expand_path("../lib/peer_nominations/approval_handler.rb", __FILE__)

  # NOTE: Badge does not implement HasCustomFields.register_custom_field_type
  # the way Topic / Post / Category / User do — calling it raises NoMethodError
  # at plugin activation (caught on staging during the first deploy attempt).
  # Badges still support custom_fields via the BadgeCustomField table, so we
  # read/write `badge.custom_fields["nominatable"]` directly. The value comes
  # back as the string "true" rather than a Boolean, which the rest of the
  # plugin already accounts for (`.to_s == "true"` checks).

  # Topic custom field registration.
  %w[peer_nom_nominator_id peer_nom_nominee_id peer_nom_badge_id].each do |field|
    Topic.register_custom_field_type(field, :integer)
  end
  Topic.register_custom_field_type(PeerNominations::TOPIC_STATE, :string)
  Topic.register_custom_field_type(PeerNominations::TOPIC_DECLINE_REASON, :string)

  # Surface the peer-nomination state on the topic_view serializer so the
  # admin Approve/Decline panel can render itself from the topic JSON.
  add_to_serializer(:topic_view, :peer_nomination) do
    state = object.topic.custom_fields[PeerNominations::TOPIC_STATE].to_s
    next nil if state.blank?

    {
      state:         state,
      nominator_id:  object.topic.custom_fields[PeerNominations::TOPIC_NOMINATOR_ID].to_i,
      nominee_id:    object.topic.custom_fields[PeerNominations::TOPIC_NOMINEE_ID].to_i,
      badge_id:      object.topic.custom_fields[PeerNominations::TOPIC_BADGE_ID].to_i,
      resolved_at:   (state == "under-review" ? nil : object.topic.updated_at),
    }
  end

  add_to_serializer(:topic_view, :include_peer_nomination?) do
    object.topic.custom_fields[PeerNominations::TOPIC_STATE].present?
  end

  # Expose nominatable + description on the badge serializer used by the
  # client when listing badges to nominate from.
  add_to_serializer(:badge, :nominatable) do
    object.custom_fields[PeerNominations::NOMINATABLE_FIELD].to_s == "true"
  end

  # Expose the current user's nomination state on the user serializer used
  # by the profile page, so the "Nominate" button knows whether to render.
  add_to_serializer(:user, :peer_nominations_visible?) do
    return false unless scope.current_user
    return false if scope.current_user.id == object.id
    SiteSetting.peer_nominations_enabled
  end
end
