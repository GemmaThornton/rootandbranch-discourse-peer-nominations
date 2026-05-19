# frozen_string_literal: true

module PeerNominations
  # Approves or declines a nomination topic.
  #
  # Approve:
  #   - Grants the badge via BadgeGranter (creates a fresh UserBadge — badges are
  #     multiple_grant, so multiple peers can each grant the same badge over time).
  #   - Inserts a peer_nomination_grants row to enforce the (nominator, nominee, badge)
  #     uniqueness rule and to keep a denormalised copy of the reason for fast
  #     admin queries later.
  #   - PMs the nominee (with the nominator's name and reason) and the nominator (confirmation).
  #   - Swaps the topic tag from "under-review" to "approved".
  #
  # Decline:
  #   - Records the decline reason on the topic.
  #   - Swaps the topic tag from "under-review" to "declined".
  #   - Closes the topic.
  #   - Sends no notifications. The nominator is not told.
  class ApprovalHandler
    Result = Struct.new(:success, :error_key, :error_args, keyword_init: true) do
      def success?; success; end
    end

    def self.approve(topic:, admin:)
      new(topic: topic, admin: admin).approve
    end

    def self.decline(topic:, admin:, decline_reason:)
      new(topic: topic, admin: admin, decline_reason: decline_reason).decline
    end

    def initialize(topic:, admin:, decline_reason: nil)
      @topic = topic
      @admin = admin
      @decline_reason = decline_reason.to_s.strip
    end

    def approve
      validation = validate
      return validation unless validation.success?

      ActiveRecord::Base.transaction do
        # BadgeGranter.grant always creates a new UserBadge when the badge is
        # multiple_grant — which it must be for nominatable badges. The seed
        # migration sets multiple_grant=true on the 9 known badges; if an
        # admin marks another badge nominatable without flipping multiple_grant,
        # subsequent grants from different peers would silently no-op. We force
        # multiple_grant on here to be safe.
        unless badge.multiple_grant
          badge.update_columns(multiple_grant: true)
        end

        user_badge = BadgeGranter.grant(badge, nominee, granted_by: @admin)
        if user_badge.nil?
          return fail(:grant_failed)
        end

        PeerNominationGrant.create!(
          nominator_id:   nominator.id,
          nominee_id:     nominee.id,
          badge_id:       badge.id,
          topic_id:       @topic.id,
          user_badge_id:  user_badge.id,
          reason:         reason_text,
          granted_at:     Time.current
        )

        swap_tag(from: PeerNominations::TAG_UNDER_REVIEW, to: PeerNominations::TAG_APPROVED)
        @topic.custom_fields[PeerNominations::TOPIC_STATE] = "approved"
        @topic.save_custom_fields(true)
      end

      send_pms!
      Result.new(success: true)
    rescue ActiveRecord::RecordNotUnique
      fail(:already_resolved)
    end

    def decline
      validation = validate
      return validation unless validation.success?

      if @decline_reason.length > 500
        return fail(:decline_reason_too_long)
      end

      swap_tag(from: PeerNominations::TAG_UNDER_REVIEW, to: PeerNominations::TAG_DECLINED)
      @topic.custom_fields[PeerNominations::TOPIC_STATE]          = "declined"
      @topic.custom_fields[PeerNominations::TOPIC_DECLINE_REASON] = @decline_reason
      @topic.save_custom_fields(true)
      @topic.update_status("closed", true, @admin)

      Result.new(success: true)
    end

    private

    def validate
      return fail(:not_admin) unless @admin&.admin? || @admin&.moderator?
      return fail(:topic_not_a_nomination) unless nominator && nominee && badge

      current_state = @topic.custom_fields[PeerNominations::TOPIC_STATE].to_s
      if current_state == "approved" || current_state == "declined"
        return fail(:already_resolved)
      end

      Result.new(success: true)
    end

    def nominator
      @nominator ||= User.find_by(id: @topic.custom_fields[PeerNominations::TOPIC_NOMINATOR_ID].to_i)
    end

    def nominee
      @nominee ||= User.find_by(id: @topic.custom_fields[PeerNominations::TOPIC_NOMINEE_ID].to_i)
    end

    def badge
      @badge ||= Badge.find_by(id: @topic.custom_fields[PeerNominations::TOPIC_BADGE_ID].to_i)
    end

    def reason_text
      # The first post's raw begins with a header and a "> reason" block. We
      # rebuild the plain reason by stripping the leading "> " from each line
      # of the quoted block.
      first_post = @topic.first_post
      raw = first_post&.raw.to_s
      lines = raw.lines.map(&:chomp)
      start = lines.index { |l| l.start_with?("> ") }
      return "" unless start
      stop = lines[start..].index { |l| !l.start_with?("> ") && !l.empty? } || lines[start..].length
      lines[start, stop].map { |l| l.sub(/^> ?/, "") }.join("\n").strip
    end

    def display_name(user)
      user.name.presence || user.username
    end

    # Markdown link to a user's profile, e.g. "[Alice Smith](/u/alice)".
    # Used in PM bodies so the nominator/nominee name is clickable.
    # Avoids @mention syntax to prevent an extra mention notification
    # firing on top of the PM itself.
    def profile_link(user)
      "[#{display_name(user)}](/u/#{user.username})"
    end

    # See NominationCreator#badge_inline_name — strips a leading "The " so
    # "the The IT Crowd badge" doesn't read as a stutter inside PM copy.
    def badge_inline_name
      badge.display_name.to_s.sub(/\A[Tt]he\s+/, "")
    end

    def swap_tag(from:, to:)
      DiscourseTagging.tag_topic_by_names(
        @topic,
        Guardian.new(@admin),
        ((@topic.tags.pluck(:name) - [from]) | [to])
      )
    end

    def send_pms!
      if nominator.id == nominee.id
        # Self-nomination: one combined PM, not two near-identical ones.
        PostCreator.create!(
          Discourse.system_user,
          title: I18n.t("peer_nominations.pm.self.title", badge: badge_inline_name),
          raw: I18n.t(
            "peer_nominations.pm.self.raw",
            nominee_name: display_name(nominee),
            badge:        badge_inline_name,
            reason:       reason_text
          ),
          archetype:    Archetype.private_message,
          target_usernames: nominee.username,
          skip_validations: true
        )
        return
      end

      PostCreator.create!(
        Discourse.system_user,
        title: I18n.t("peer_nominations.pm.nominee.title", badge: badge_inline_name),
        raw: I18n.t(
          "peer_nominations.pm.nominee.raw",
          nominee_name:   display_name(nominee),
          nominator_name: display_name(nominator),
          nominator_link: profile_link(nominator),
          badge:          badge_inline_name,
          reason:         reason_text
        ),
        archetype:    Archetype.private_message,
        target_usernames: nominee.username,
        skip_validations: true
      )

      PostCreator.create!(
        Discourse.system_user,
        title: I18n.t("peer_nominations.pm.nominator.title", nominee: display_name(nominee)),
        raw: I18n.t(
          "peer_nominations.pm.nominator.raw",
          nominator_name: display_name(nominator),
          nominee_name:   display_name(nominee),
          nominee_link:   profile_link(nominee),
          badge:          badge_inline_name
        ),
        archetype:    Archetype.private_message,
        target_usernames: nominator.username,
        skip_validations: true
      )
    end

    def fail(key, **args)
      Result.new(success: false, error_key: key, error_args: args)
    end
  end
end
