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

    # Nominee-initiated decline — revokes the granted badge, deletes the
    # grant row, and parks the original nomination topic in
    # "declined-by-nominee" state.
    def self.decline_as_nominee(topic:, nominee:)
      new(topic: topic, admin: Discourse.system_user).decline_as_nominee(nominee)
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

        # Note: approval intentionally does NOT auto-add to groups, even
        # for Known Lefty. Group access (Verified Socialists / district
        # group) is a separate admin decision — exposed via the two
        # add-nominee-to-* buttons on the admin panel — so that members
        # collect multiple Known Lefty grants before being promoted to
        # organising spaces. See nominations_controller#add_nominee_to_*.

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

    # Nominee-initiated decline. The badge has already been granted; this
    # reverses it. Verifies the topic was actually approved and that the
    # caller is the recorded nominee.
    def decline_as_nominee(declining_user)
      return fail(:topic_not_a_nomination) unless nominator && nominee && badge
      return fail(:not_admin) unless declining_user&.id == nominee.id

      current_state = @topic.custom_fields[PeerNominations::TOPIC_STATE].to_s
      unless current_state == "approved"
        return fail(:already_resolved)
      end

      ActiveRecord::Base.transaction do
        grant = PeerNominationGrant.find_by(topic_id: @topic.id)
        if grant
          user_badge = UserBadge.find_by(id: grant.user_badge_id)
          if user_badge
            BadgeGranter.revoke(user_badge)
          end
          grant.destroy
        end

        swap_tag(from: PeerNominations::TAG_APPROVED, to: PeerNominations::TAG_DECLINED_BY_NOMINEE)
        @topic.custom_fields[PeerNominations::TOPIC_STATE] = "declined-by-nominee"
        @topic.save_custom_fields(true)
        @topic.update_status("closed", true, Discourse.system_user)
      end

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

    # Stamps the nominee's approval PM with peer_nom_decline_for_topic_id
    # so the in-PM "Decline this badge" connector renders for them. Points
    # back to the original nomination topic — the decline action runs
    # against that topic's state, not the PM.
    def mark_pm_offers_decline!(post)
      pm_topic = post&.topic
      return unless pm_topic
      pm_topic.custom_fields[PeerNominations::PM_DECLINE_FOR_TOPIC] = @topic.id
      pm_topic.save_custom_fields(true)
    end

    # The %{decline_link} placeholder in the nominee/self PM bodies gets
    # populated with a markdown link AFTER the PM is created — we need
    # the PM topic's own URL to build the link, and that URL only exists
    # after PostCreator.create! returns. Using this sentinel during the
    # initial create then swapping it in via update_columns avoids both
    # a) regenerating the entire raw twice and b) a Post.revise-style
    # "edited" marker on the brand-new system message.
    DECLINE_LINK_PLACEHOLDER = "__PEER_NOM_DECLINE_LINK__"

    def send_pms!
      if nominator.id == nominee.id
        # Self-nomination: one combined PM, not two near-identical ones.
        self_post = PostCreator.create!(
          Discourse.system_user,
          title: I18n.t("peer_nominations.pm.self.title", badge: badge_inline_name),
          raw: self_pm_raw(DECLINE_LINK_PLACEHOLDER),
          archetype:    Archetype.private_message,
          target_usernames: nominee.username,
          skip_validations: true
        )
        finalize_decline_link!(self_post) { |link| self_pm_raw(link) }
        mark_pm_offers_decline!(self_post)
        return
      end

      nominee_post = PostCreator.create!(
        Discourse.system_user,
        title: I18n.t("peer_nominations.pm.nominee.title", badge: badge_inline_name),
        raw: nominee_pm_raw(DECLINE_LINK_PLACEHOLDER),
        archetype:    Archetype.private_message,
        target_usernames: nominee.username,
        skip_validations: true
      )
      finalize_decline_link!(nominee_post) { |link| nominee_pm_raw(link) }
      mark_pm_offers_decline!(nominee_post)

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

    # Render the nominee approval PM body. Takes the decline link as a
    # parameter so we can pass a placeholder string at PostCreator time
    # then the real markdown link after the PM topic id is known.
    def nominee_pm_raw(decline_link)
      I18n.t(
        "peer_nominations.pm.nominee.raw",
        nominee_name:   display_name(nominee),
        nominator_name: display_name(nominator),
        nominator_link: profile_link(nominator),
        badge:          badge_inline_name,
        reason:         reason_text,
        decline_link:   decline_link
      )
    end

    # Same shape as nominee_pm_raw, for self-nominations.
    def self_pm_raw(decline_link)
      I18n.t(
        "peer_nominations.pm.self.raw",
        nominee_name: display_name(nominee),
        badge:        badge_inline_name,
        reason:       reason_text,
        decline_link: decline_link
      )
    end

    # Rebuild the PM's raw+cooked once the topic id (and hence URL) is
    # known. Uses update_columns to skip the Post#save callbacks that
    # would otherwise log an "edited" revision on a freshly-created
    # system message. The PM-notification email job runs later via
    # Sidekiq and reads the post fresh, so the email body picks up the
    # finalised link automatically.
    def finalize_decline_link!(post)
      pm_url = post.topic.url
      link_md = "[click here to decline this badge](#{pm_url})"
      final_raw = yield(link_md)
      cooked = PrettyText.cook(final_raw)
      post.update_columns(raw: final_raw, cooked: cooked)
    end

    def fail(key, **args)
      Result.new(success: false, error_key: key, error_args: args)
    end
  end
end
