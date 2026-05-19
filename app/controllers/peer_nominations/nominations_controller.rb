# frozen_string_literal: true

module PeerNominations
  class NominationsController < ::ApplicationController
    before_action :ensure_logged_in
    before_action :ensure_enabled

    # GET /peer-nominations/nominatable-badges
    # Returns the nominatable badges (from the hardcoded list in plugin.rb),
    # with the badge description so the nominator can see what each badge
    # is for from the picker.
    def nominatable_badges
      badges = Badge
        .where(name: PeerNominations::NOMINATABLE_BADGE_NAMES, enabled: true)
        .order(:name)

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
        nominator: current_user,
        nominee:   nominee,
        badge:     badge,
        reason:    params[:reason].to_s
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

    private

    def locate_topic
      topic = Topic.find_by(id: params[:topic_id].to_i)
      raise Discourse::NotFound unless topic
      topic
    end

    def ensure_enabled
      raise Discourse::NotFound unless SiteSetting.peer_nominations_enabled
    end

    def error_status_for(key)
      case key
      when :trust_level, :not_admin
        :forbidden
      when :rate_limited
        :too_many_requests
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
