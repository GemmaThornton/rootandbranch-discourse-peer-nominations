# frozen_string_literal: true

module PeerNominations
  # Filters UserBadge records by viewer eligibility for the
  # corresponding PeerNominationGrant's visibility_scope.
  #
  # A UserBadge with no matching grant (e.g. a Discourse system-awarded
  # badge or an admin-granted badge without a nomination) is always
  # visible — the filter only narrows badges that PEER NOMINATIONS
  # granted with a restrictive scope.
  module BadgeVisibility
    SCOPE_PUBLIC     = "public"
    SCOPE_VS_ONLY    = "vs_only"
    SCOPE_ADMIN_ONLY = "admin_only"

    VS_VIEWER_GROUP_NAME    = "VerifiedLeft"
    ADMIN_VIEWER_GROUP_NAME = "Core"

    # Returns the subset of user_badges that `viewer` is allowed to see.
    # viewer may be nil (anonymous).
    def self.filter(user_badges, viewer)
      return user_badges if user_badges.blank?

      user_badge_ids = user_badges.map { |ub| ub.respond_to?(:id) ? ub.id : ub["id"] }.compact
      return user_badges if user_badge_ids.empty?

      grants = PeerNominationGrant
        .where(user_badge_id: user_badge_ids)
        .pluck(:user_badge_id, :visibility_scope, :nominee_id)
        .each_with_object({}) do |(ub_id, scope, nominee_id), h|
          h[ub_id] = { scope: scope, nominee_id: nominee_id }
        end

      return user_badges if grants.empty?

      viewer_id = viewer&.id
      viewer_is_staff = viewer&.staff? || false
      viewer_in_vs = viewer && Group.exists?(name: VS_VIEWER_GROUP_NAME) &&
                     GroupUser.exists?(
                       group_id: Group.where(name: VS_VIEWER_GROUP_NAME).select(:id),
                       user_id:  viewer.id,
                     )
      viewer_in_admin_audience = viewer && Group.exists?(name: ADMIN_VIEWER_GROUP_NAME) &&
                                 GroupUser.exists?(
                                   group_id: Group.where(name: ADMIN_VIEWER_GROUP_NAME).select(:id),
                                   user_id:  viewer.id,
                                 )

      user_badges.select do |ub|
        ub_id = ub.respond_to?(:id) ? ub.id : ub["id"]
        info = grants[ub_id]
        next true unless info  # not a peer-nomination grant

        scope = info[:scope] || SCOPE_PUBLIC
        case scope
        when SCOPE_PUBLIC
          true
        when SCOPE_VS_ONLY
          viewer_id == info[:nominee_id] || viewer_is_staff || viewer_in_vs
        when SCOPE_ADMIN_ONLY
          viewer_id == info[:nominee_id] || viewer_is_staff || viewer_in_admin_audience
        else
          true
        end
      end
    end
  end
end
