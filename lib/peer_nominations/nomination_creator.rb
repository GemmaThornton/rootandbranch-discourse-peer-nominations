# frozen_string_literal: true

module PeerNominations
  # Creates a nomination as a topic in the configured admin-only category.
  # The topic IS the nomination — its custom fields store nominator/nominee/badge,
  # its tags carry the state, its first post carries the reason.
  class NominationCreator
    Result = Struct.new(:success, :topic, :error_key, :error_args, keyword_init: true) do
      def success?; success; end
    end

    def self.call(nominator:, nominee:, badge:, reason:)
      new(nominator: nominator, nominee: nominee, badge: badge, reason: reason).call
    end

    def initialize(nominator:, nominee:, badge:, reason:)
      @nominator = nominator
      @nominee   = nominee
      @badge     = badge
      @reason    = reason.to_s.strip
    end

    def call
      category_id = SiteSetting.peer_nominations_category_id.to_i
      return fail(:not_configured) if category_id.zero?

      # Self-nominations are intentionally allowed. The admin review step is
      # the gate — if a self-nomination is unconvincing the admin declines.
      return fail(:badge_not_nominatable) unless badge_nominatable?

      min_tl = SiteSetting.peer_nominations_min_trust_level
      return fail(:trust_level) if @nominator.trust_level < min_tl

      min = SiteSetting.peer_nominations_min_reason_length
      max = SiteSetting.peer_nominations_max_reason_length
      return fail(:reason_too_short, min: min) if @reason.length < min
      return fail(:reason_too_long, max: max)  if @reason.length > max

      if PeerNominationGrant.exists?(nominator_id: @nominator.id, nominee_id: @nominee.id, badge_id: @badge.id)
        return fail(:already_approved)
      end

      if rate_limited?
        return fail(:rate_limited,
                    count: SiteSetting.peer_nominations_rate_limit_count,
                    days:  SiteSetting.peer_nominations_rate_limit_window_days)
      end

      topic = create_topic(category_id)
      return fail(:generic) unless topic

      Result.new(success: true, topic: topic)
    end

    private

    def badge_nominatable?
      @badge.custom_fields[PeerNominations::NOMINATABLE_FIELD].to_s == "true"
    end

    def rate_limited?
      window_start = SiteSetting.peer_nominations_rate_limit_window_days.days.ago
      limit        = SiteSetting.peer_nominations_rate_limit_count

      Topic
        .joins(:_custom_fields)
        .where(topic_custom_fields: { name: PeerNominations::TOPIC_NOMINATOR_ID, value: @nominator.id.to_s })
        .where("topics.created_at >= ?", window_start)
        .count >= limit
    end

    def create_topic(category_id)
      self_nomination = @nominator.id == @nominee.id

      title = I18n.t(
        self_nomination ? "peer_nominations.topic.title_self" : "peer_nominations.topic.title",
        nominator: display_name(@nominator),
        nominee:   display_name(@nominee),
        badge:     @badge.display_name
      )

      raw = I18n.t(
        self_nomination ? "peer_nominations.topic.body_self" : "peer_nominations.topic.body",
        nominator: display_name(@nominator),
        nominee:   display_name(@nominee),
        badge:     @badge.display_name,
        reason:    @reason.gsub(/\r?\n/, "\n> ")
      )

      creator = PostCreator.new(
        Discourse.system_user,
        title: title,
        raw: raw,
        category: category_id,
        tags: [PeerNominations::TAG_UNDER_REVIEW],
        skip_validations: true,
        skip_jobs: true
      )
      post = creator.create

      if post.nil? || creator.errors.any?
        Rails.logger.warn("[PeerNominations] PostCreator failed: #{creator.errors.full_messages.join(', ')}")
        return nil
      end

      topic = post.topic
      topic.custom_fields[PeerNominations::TOPIC_NOMINATOR_ID] = @nominator.id
      topic.custom_fields[PeerNominations::TOPIC_NOMINEE_ID]   = @nominee.id
      topic.custom_fields[PeerNominations::TOPIC_BADGE_ID]     = @badge.id
      topic.custom_fields[PeerNominations::TOPIC_STATE]        = "under-review"
      topic.save_custom_fields(true)
      topic
    end

    def display_name(user)
      user.name.presence || user.username
    end

    def fail(key, **args)
      Result.new(success: false, error_key: key, error_args: args)
    end
  end
end
