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

  # The set of admin-created badges that members can nominate each other for.
  # Match is by exact `Badge.name`. Order in this list is the order shown to
  # nominators in the picker dropdown — keep the most important badge first.
  # Renaming a badge here means it stops being nominatable — keep this list
  # in step with admin-side badge renames.
  NOMINATABLE_BADGE_NAMES = [
    "Proper Lefty",
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

  # Special-case badge that, when approved, also adds the nominee to the
  # forum's verification group (read access to the National Organising
  # category) and their local <District> Verified Socialists (GP) group.
  # The group-add logic for the district side reuses the existing Red Star
  # plugin's `VsGpDistrictAssigner` — both plugins are loaded into the
  # same Discourse app, so the constant is reachable.
  PROPER_LEFTY_BADGE_NAME = "Proper Lefty"

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

  # NOTE: Badge in current Discourse (8.x) does NOT expose .custom_fields
  # the way Topic / Post / Category / User do — both register_custom_field_type
  # AND the .custom_fields read/write accessor raise NoMethodError. So we
  # don't try to store "nominatable" on the badge at all; we keep the list of
  # nominatable badges as a frozen constant (PeerNominations::NOMINATABLE_BADGE_NAMES)
  # and match by Badge.name in the controller and the nomination creator.

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

  # Expose the current user's nomination state on the user serializer used
  # by the profile page, so the "Nominate" button knows whether to render.
  add_to_serializer(:user, :peer_nominations_visible?) do
    return false unless scope.current_user
    return false if scope.current_user.id == object.id
    SiteSetting.peer_nominations_enabled
  end
end
