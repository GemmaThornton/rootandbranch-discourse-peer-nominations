# frozen_string_literal: true

module PeerNominations
  class NominationsController < ::ApplicationController
    before_action :ensure_logged_in
    before_action :ensure_enabled
    before_action :ensure_staff_for_group_actions, only: [:add_nominee_to_national_group, :add_nominee_to_district_group]
    before_action :ensure_admin, only: [:admin_received_for_user]

    # GET /peer-nominations/nominatable-badges
    # Returns the nominatable badges (from the hardcoded list in plugin.rb),
    # in the order they appear in NOMINATABLE_BADGE_NAMES — so the picker
    # dropdown reflects plugin-defined priority (e.g. Known Lefty first)
    # rather than alphabetical.
    def nominatable_badges
      enabled_by_name = Badge
        .where(name: PeerNominations::NOMINATABLE_BADGE_NAMES, enabled: true)
        .index_by(&:name)

      badges = PeerNominations::NOMINATABLE_BADGE_NAMES
        .map { |n| enabled_by_name[n] }
        .compact

      render json: {
        badges: ActiveModel::ArraySerializer.new(
          badges,
          each_serializer: PeerNominations::NominatableBadgeSerializer,
          root: false
        ).as_json
      }
    end

    # POST /peer-nominations
    # body: { username: "...", badge_id: 123, reason: "..." }
    def create
      nominee = User.find_by(username_lower: params[:username].to_s.downcase)
      raise Discourse::NotFound unless nominee

      badge = Badge.find_by(id: params[:badge_id].to_i)
      raise Discourse::NotFound unless badge

      result = NominationCreator.call(
        nominator:        current_user,
        nominee:          nominee,
        badge:            badge,
        reason:           params[:reason].to_s,
        where_known_from: params[:where_known_from].to_s,
        how_long_known:   params[:how_long_known].to_s
      )

      if result.success?
        render json: {
          topic_id:   result.topic.id,
          topic_url:  result.topic.url
        }, status: :created
      else
        render json: {
          error: I18n.t("peer_nominations.errors.#{result.error_key}", **(result.error_args || {}))
        }, status: error_status_for(result.error_key)
      end
    end

    # POST /peer-nominations/:topic_id/approve
    def approve
      topic = locate_topic
      result = ApprovalHandler.approve(topic: topic, admin: current_user)

      if result.success?
        render json: success_json
      else
        render json: { error: I18n.t("peer_nominations.errors.#{result.error_key}") },
               status: error_status_for(result.error_key)
      end
    end

    # POST /peer-nominations/:topic_id/add-nominee-to-national-group
    # Adds the nomination topic's nominee to the forum's verification
    # group (whatever red_star_verification_group_name is set to —
    # gives read access to the National Organising category). Used
    # by the admin panel's "Add to Verified Socialists" button.
    # Idempotent — already-in-group returns 200 with status "already".
    def add_nominee_to_national_group
      topic = locate_topic
      user_obj = nominee_for(topic)
      raise Discourse::NotFound unless user_obj

      group_name = SiteSetting.red_star_verification_group_name
      if group_name.blank?
        return render json: { error: "Verification group is not configured (site setting `red_star_verification_group_name`)." },
                      status: :unprocessable_entity
      end

      group = Group.find_by(name: group_name)
      unless group
        return render json: { error: "Verification group #{group_name.inspect} not found." },
                      status: :unprocessable_entity
      end

      if GroupUser.exists?(group_id: group.id, user_id: user_obj.id)
        return render json: { status: "already", label: friendly_group_label(group) }
      end

      group.add(user_obj)
      render json: { status: "added", label: friendly_group_label(group) }
    end

    # POST /peer-nominations/:topic_id/add-nominee-to-district-group
    # Adds the nomination topic's nominee to their district's
    # vs_gp_<slug> "Verified Socialists (GP)" group, creating the
    # group + category lazily via the existing Red Star plugin's
    # VsGpDistrictAssigner. Returns a friendly error if the nominee
    # has no postcode/district set.
    def add_nominee_to_district_group
      topic = locate_topic
      user_obj = nominee_for(topic)
      raise Discourse::NotFound unless user_obj

      unless defined?(::RedStarEndorsements::VsGpDistrictAssigner)
        return render json: { error: "District assigner not available — the Red Star plugin must be installed alongside peer-nominations." },
                      status: :unprocessable_entity
      end

      result = ::RedStarEndorsements::VsGpDistrictAssigner.add_user_to_district_group(user_obj)

      case
      when result[:ok]
        render json: { status: "added", label: result[:category_name] }
      when result[:error] == :not_green_party
        render json: { error: "#{user_obj.username} isn't in the Green Party Members group, so they can't be added to a District Verified Socialists (GP) group." },
               status: :unprocessable_entity
      when result[:error] == :not_verified
        render json: { error: "#{user_obj.username} hasn't been added to the verification group (#{SiteSetting.red_star_verification_group_name}) yet — do that first, then this button will work." },
               status: :unprocessable_entity
      when result[:error] == :no_district
        render json: { error: "#{user_obj.username} has no postcode or district set — they need to fill that in before they can be added to a district group." },
               status: :unprocessable_entity
      when result[:error] == :already_in_group
        label = "#{result[:district]}#{::RedStarEndorsements::VsGpDistrictAssigner::CATEGORY_SUFFIX}"
        render json: { status: "already", label: label }
      else
        Rails.logger.warn("[PeerNominations] district add failed for user #{user_obj.id}: #{result.inspect}")
        render json: { error: "Could not add to district group — check the logs." },
               status: :unprocessable_entity
      end
    end

    # POST /peer-nominations/:topic_id/decline-as-nominee
    # Nominee-initiated decline of an already-approved badge. Reverses
    # the BadgeGranter.grant, deletes the PeerNominationGrant row, and
    # marks the original topic as "declined-by-nominee". Guarded so
    # only the topic's nominee can call it.
    def decline_as_nominee
      topic = locate_topic
      result = ApprovalHandler.decline_as_nominee(topic: topic, nominee: current_user)

      if result.success?
        render json: success_json
      else
        render json: { error: I18n.t("peer_nominations.errors.#{result.error_key}") },
               status: error_status_for(result.error_key)
      end
    end

    # POST /peer-nominations/:topic_id/decline
    # body: { decline_reason: "..." }
    def decline
      topic = locate_topic
      result = ApprovalHandler.decline(
        topic: topic,
        admin: current_user,
        decline_reason: params[:decline_reason].to_s
      )

      if result.success?
        render json: success_json
      else
        render json: { error: I18n.t("peer_nominations.errors.#{result.error_key}") },
               status: error_status_for(result.error_key)
      end
    end

    # GET /peer-nominations/admin/users/:user_id/received
    # Returns the list of approved peer-nomination grants RECEIVED by the
    # given user (i.e. they were the nominee). Admin-only — powers the
    # "Peer nominations received" panel on user profiles so admins can
    # retrieve the full nomination context (nominator, badge, reason,
    # link back to the original — possibly archived — topic) after
    # approval.
    def admin_received_for_user
      user = User.find_by(id: params[:user_id].to_i)
      raise Discourse::NotFound unless user

      grants = PeerNominationGrant
        .where(nominee_id: user.id)
        .includes(:nominator, :badge, :topic)
        .order(granted_at: :desc)

      render json: {
        grants: ActiveModel::ArraySerializer.new(
          grants,
          each_serializer: AdminGrantSerializer,
          root: false
        ).as_json
      }
    end

    private

    def ensure_admin
      raise Discourse::InvalidAccess unless current_user&.admin?
    end

    def locate_topic
      topic = Topic.find_by(id: params[:topic_id].to_i)
      raise Discourse::NotFound unless topic
      topic
    end

    def nominee_for(topic)
      User.find_by(id: topic.custom_fields[PeerNominations::TOPIC_NOMINEE_ID].to_i)
    end

    def friendly_group_label(group)
      group.full_name.presence || group.name
    end

    def ensure_enabled
      raise Discourse::NotFound unless SiteSetting.peer_nominations_enabled
    end

    def ensure_staff_for_group_actions
      raise Discourse::InvalidAccess unless current_user&.admin? || current_user&.moderator?
    end

    def error_status_for(key)
      case key
      when :trust_level, :not_admin
        :forbidden
      when :already_approved, :already_resolved
        :conflict
      when :topic_not_a_nomination, :badge_not_found, :badge_not_nominatable
        :not_found
      else
        :unprocessable_entity
      end
    end
  end
end
